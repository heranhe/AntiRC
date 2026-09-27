//
//  RemoteWebView.swift
//  AntigravityRemote
//
//  核心 WKWebView 封装，深度适配灵动岛、安全区，注入防拦截 UA，并支持下拉刷新与侧滑
//

import SwiftUI
import WebKit

/// 网页控制器状态与动作载体
public final class WebViewModel: ObservableObject {
    @Published public var currentURL: URL?
    @Published public var pageTitle: String = ""
    @Published public var progress: Double = 0.0
    @Published public var isLoading: Bool = false
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var loadError: String? = nil
    
    @Published var messages: [ConversationMessage] = []
    @Published var conversationSupported = false
    @Published var canSendMessage = false
    @Published var isResponding = false
    @Published var canStopResponse = false
    @Published var isSubmitting = false
    @Published var composerError: String?
    @Published var projects: [RemoteProject] = []
    @Published var modelLabel = ""
    @Published var modelOptions: [RemoteModelOption] = []
    @Published var usageGroups: [UsageGroup] = []
    @Published var workspaceBusy = false
    @Published var workspaceError: String?
    @Published var attachmentNotice: String?
    @Published var attachmentPreview: Data?
    @Published var isAttaching = false
    var attachImageAction: ((Data, String, String, @escaping (Bool) -> Void) -> Void)?
    var submitMessageAction: ((String, @escaping (Bool) -> Void) -> Void)?
    var stopResponseAction: (() -> Void)?
    var openConversationAction: ((String) -> Void)?
    var expandProjectAction: ((String) -> Void)?
    var openModelsAction: (() -> Void)?
    var selectModelAction: ((String, @escaping (Bool) -> Void) -> Void)?
    var openUsageAction: (() -> Void)?
    var closePanelsAction: (() -> Void)?

    func resetConversation() {
        messages = []
        conversationSupported = false
        canSendMessage = false
        isResponding = false
        canStopResponse = false
        composerError = nil
        isSubmitting = false
        projects = []
        modelLabel = ""
        modelOptions = []
        usageGroups = []
        workspaceBusy = false
        workspaceError = nil
        attachmentNotice = nil
        attachmentPreview = nil
        isAttaching = false
    }

    func apply(_ state: ConversationSnapshot) {
        messages = state.messages
        conversationSupported = state.supported
        canSendMessage = state.canSend
        isResponding = state.isRunning
        canStopResponse = state.canStop
        guard let workspace = state.workspace else { return }
        projects = workspace.projects
        modelLabel = workspace.model
        if !workspace.models.isEmpty { modelOptions = workspace.models }
        if !workspace.usage.isEmpty { usageGroups = workspace.usage }
    }

    func openConversation(_ id: String) { openConversationAction?(id) }
    func expandProject(_ title: String) { expandProjectAction?(title) }
    func openModels() { openModelsAction?() }
    func selectModel(_ id: String, completion: @escaping (Bool) -> Void) {
        guard let selectModelAction else { completion(false); return }
        selectModelAction(id, completion)
    }
    func openUsage() { openUsageAction?() }

    func attachImage(_ data: Data, name: String, type: String, completion: @escaping (Bool) -> Void) {
        guard let attachImageAction, !isAttaching else { completion(false); return }
        isAttaching = true
        attachImageAction(data, name, type) { [weak self] succeeded in
            self?.isAttaching = false
            self?.attachmentNotice = succeeded ? "图片已交给网页处理，可打开原版查看上传结果。" : "图片未添加，请重试或打开原版页面。"
            if succeeded { self?.attachmentPreview = data }
            completion(succeeded)
        }
    }

    func submitMessage(_ text: String, completion: @escaping (Bool) -> Void) {
        guard !isSubmitting, canSendMessage, !isResponding, let action = submitMessageAction else {
            completion(false)
            return
        }
        isSubmitting = true
        composerError = nil
        action(text) { [weak self] succeeded in
            self?.isSubmitting = false
            if succeeded { self?.attachmentPreview = nil; self?.attachmentNotice = nil }
            completion(succeeded)
        }
    }

    // 动作触发器（通过闭包与 WKWebView 桥接）
    var reloadAction: (() -> Void)?
    var goBackAction: (() -> Void)?
    var goForwardAction: (() -> Void)?
    var sendKeyAction: ((String, Bool) -> Void)?
    
    public init(initialURL: URL? = nil) {
        self.currentURL = initialURL
    }
    
    public func reload() {
        reloadAction?()
    }
    
    public func goBack() {
        goBackAction?()
    }
    
    public func goForward() {
        goForwardAction?()
    }
    
    public func sendKey(key: String, ctrl: Bool = false) {
        sendKeyAction?(key, ctrl)
    }
}

/// SwiftUI 包装的 WKWebView
public struct RemoteWebView: UIViewRepresentable {
    @ObservedObject public var viewModel: WebViewModel
    public var userAgent: String
    public var onAccountIdentified: ((String) -> Void)?
    
    public init(viewModel: WebViewModel, userAgent: String, onAccountIdentified: ((String) -> Void)? = nil) {
        self.viewModel = viewModel
        self.userAgent = userAgent
        self.onAccountIdentified = onAccountIdentified
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // 允许内联视频播放与全屏
        config.allowsInlineMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        
        // 采用持久化数据仓库，保存登录态和 Cookie
        config.websiteDataStore = .default()
        
        // 注入自适应 Viewport 与 CSS 脚本
        let viewportScriptSource = """
        (function() {
            var meta = document.querySelector('meta[name="viewport"]');
            if (meta) {
                if (!meta.content.includes('viewport-fit=cover')) {
                    meta.content += ', viewport-fit=cover';
                }
            } else {
                var newMeta = document.createElement('meta');
                newMeta.name = 'viewport';
                newMeta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover';
                document.head.appendChild(newMeta);
            }
        })();
        """
        let userScript = WKUserScript(
            source: viewportScriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        // Google 账号页兼容脚本：隐藏内嵌特征、避开蓝牙通行密钥拦截（防 403 / 蓝牙引导）
        let googleCompatScript = WKUserScript(
            source: GoogleSignInGate.compatibilityScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(googleCompatScript)

        config.userContentController.add(context.coordinator, name: "conversation")
        config.userContentController.addUserScript(WKUserScript(
            source: ConversationBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
#if DEBUG
        webView.isInspectable = true
#endif
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // 深色背景：避免加载期间白屏与暗色 UI 冲突
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        
        // 设置合规 User-Agent，规避 Google OAuth 403 disallowed_useragent
        webView.customUserAgent = userAgent
        
        // 允许边缘侧滑前进后退
        webView.allowsBackForwardNavigationGestures = true
        
        // 配置滚动视图属性
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        
        // 配置原生下拉刷新
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        // 绑定 ViewModel 中的动作
        context.coordinator.setupActions(for: webView)
        
        // 监听加载进度与标题
        context.coordinator.setupObservers(for: webView)
        
        // 发起初始请求
        if let url = viewModel.currentURL {
            context.coordinator.lastLoadedURL = url
            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            webView.load(request)
        }
        
        return webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // 如果 UA 发生改变，实时刷新 UA
        if uiView.customUserAgent != userAgent {
            uiView.customUserAgent = userAgent
        }
        // 如果切换到了不同的新 URL，才触发重新加载；同一 URL 保持不变，实现 0 秒瞬间恢复
        if let targetURL = viewModel.currentURL,
           targetURL != context.coordinator.lastLoadedURL {
            context.coordinator.lastLoadedURL = targetURL
            let request = URLRequest(url: targetURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            uiView.load(request)
        }
    }
    
    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "conversation")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var lastLoadedURL: URL?
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: body),
                  let state = try? JSONDecoder().decode(ConversationSnapshot.self, from: data) else { return }
            let source = body["frameID"] as? String ?? "main"
            let priority = state.supported || state.canSend ? 2 : (state.workspace?.projects.isEmpty == false ? 1 : 0)
            // Keep snapshots and actions bound to the same document, including cross-origin frames.
            guard source == activeFrameID || activeFrameID == nil || priority > activeFramePriority else { return }
            activeFrameID = source
            activeFramePriority = priority
            activeFrame = message.frameInfo
            let apply = { self.parent.viewModel.apply(state) }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }

        var parent: RemoteWebView
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?
        private weak var webView: WKWebView?
        private var activeFrame: WKFrameInfo?
        private var activeFrameID: String?
        private var activeFramePriority = 0
        
        init(_ parent: RemoteWebView) {
            self.parent = parent
        }
        
        deinit {
            progressObservation?.invalidate()
            titleObservation?.invalidate()
            canGoBackObservation?.invalidate()
            canGoForwardObservation?.invalidate()
        }
        
        func setupActions(for webView: WKWebView) {
            self.webView = webView
            parent.viewModel.submitMessageAction = { [weak self, weak webView] text, completion in
                guard let webView else { completion(false); return }
                webView.callAsyncJavaScript(
                    "return await window.__antiConversation?.send(text) ?? 'unavailable';",
                    arguments: ["text": text], in: self?.activeFrame, in: .page
                ) { result in
                    let submitted: Bool
                    if case .success(let value) = result, let status = value as? String {
                        submitted = status == "submitted"
                        if !submitted {
                            self?.parent.viewModel.composerError = status == "draft-conflict"
                                ? "网页中已有草稿，请打开网页处理后再发送。"
                                : "尚未发送。请打开网页检查输入框；内容已保留。"
                        }
                    } else {
                        submitted = false
                        self?.parent.viewModel.composerError = "发送未确认，请打开网页检查，避免重复发送。"
                    }
                    completion(submitted)
                }
            }
            parent.viewModel.stopResponseAction = { [weak self] in
                self?.perform("stop") { succeeded in
                    if !succeeded {
                        self?.parent.viewModel.composerError = "未能停止回复，请打开网页操作。"
                    }
                }
            }
            parent.viewModel.openConversationAction = { [weak self] id in
                self?.perform("openConversation", value: id)
            }
            parent.viewModel.expandProjectAction = { [weak self] title in
                self?.perform("expandProject", value: title)
            }
            parent.viewModel.openModelsAction = { [weak self] in
                self?.parent.viewModel.modelOptions = []
                self?.perform("openModels")
            }
            parent.viewModel.selectModelAction = { [weak self] label, completion in
                self?.perform("selectModel", value: label, completion: completion)
            }
            parent.viewModel.openUsageAction = { [weak self] in
                self?.parent.viewModel.usageGroups = []
                self?.perform("openUsage")
            }
            parent.viewModel.closePanelsAction = { [weak self, weak webView] in
                webView?.callAsyncJavaScript(
                    "return await window.__antiConversation?.closePanels() ?? false;",
                    arguments: [:], in: self?.activeFrame, in: .page
                ) { _ in }
            }
            parent.viewModel.attachImageAction = { [weak self, weak webView] data, name, type, completion in
                guard let webView else { completion(false); return }
                webView.callAsyncJavaScript(
                    "return await window.__antiConversation?.attachImage(payload) ?? false;",
                    arguments: ["payload": ["base64": data.base64EncodedString(), "name": name, "type": type]],
                    in: self?.activeFrame, in: .page
                ) { result in
                    if case .success(let value) = result { completion((value as? Bool) == true) }
                    else { completion(false) }
                }
            }
            
            parent.viewModel.reloadAction = { [weak webView] in
                webView?.reload()
            }
            
            parent.viewModel.goBackAction = { [weak webView] in
                if webView?.canGoBack == true {
                    webView?.goBack()
                }
            }
            
            parent.viewModel.goForwardAction = { [weak webView] in
                if webView?.canGoForward == true {
                    webView?.goForward()
                }
            }
            
            parent.viewModel.sendKeyAction = { [weak webView] key, ctrl in
                // 向网页活动元素派发键盘事件（支持终端快捷键如 Ctrl+C、Enter、Esc）
                let script = """
                (function() {
                    const active = document.activeElement || document.body;
                    const event = new KeyboardEvent('keydown', {
                        key: '\(key)',
                        code: '\(key)',
                        ctrlKey: \(ctrl),
                        metaKey: \(ctrl),
                        bubbles: true,
                        cancelable: true
                    });
                    active.dispatchEvent(event);
                })();
                """
                webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }

        private func perform(_ action: String, value: String = "", completion: ((Bool) -> Void)? = nil) {
            guard let webView else { completion?(false); return }
            parent.viewModel.workspaceBusy = true
            parent.viewModel.workspaceError = nil
            webView.callAsyncJavaScript(
                "return await window.__antiConversation?.[action]?.(value) ?? false;",
                arguments: ["action": action, "value": value], in: activeFrame, in: .page
            ) { [weak self] result in
                guard let self else { completion?(false); return }
                let succeeded: Bool
                if case .success(let value) = result { succeeded = (value as? Bool) == true }
                else { succeeded = false }
                self.parent.viewModel.workspaceBusy = false
                if !succeeded {
                    self.parent.viewModel.workspaceError = "网页未确认这次操作。请重试，或打开原版页面检查。"
                }
                completion?(succeeded)
            }
        }
        
        func setupObservers(for webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.viewModel.progress = view.estimatedProgress
                }
            }
            
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    if let title = view.title, !title.isEmpty {
                        self?.parent.viewModel.pageTitle = title
                    }
                }
            }
            
            canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.viewModel.canGoBack = view.canGoBack
                }
            }
            
            canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.viewModel.canGoForward = view.canGoForward
                }
            }
        }
        
        @objc func handleRefresh(_ sender: UIRefreshControl) {
            HapticManager.heavy()
            webView?.reload()
        }

        // MARK: - WKNavigationDelegate
        
        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            activeFrame = nil
            activeFrameID = nil
            activeFramePriority = 0
            DispatchQueue.main.async {
                self.parent.viewModel.resetConversation()
                self.parent.viewModel.isLoading = true
                self.parent.viewModel.loadError = nil
            }
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 清理可能残留的 zoom 样式，恢复原生视口布局
            let resetScript = """
            (function() {
                try {
                    if (document.documentElement.style.zoom) {
                        document.documentElement.style.zoom = '';
                    }
                } catch(e) {}
            })();
            """
            webView.evaluateJavaScript(resetScript, completionHandler: nil)
            
            DispatchQueue.main.async {
                self.parent.viewModel.isLoading = false
                webView.scrollView.refreshControl?.endRefreshing()
                if let url = webView.url {
                    self.parent.viewModel.currentURL = url
                }
            }
            
            // 尝试智能探测提取已登录的 Google 账户标识或工作区标题
            let extractScript = """
            (function() {
                try {
                    var emailElem = document.querySelector('[data-email]') || document.querySelector('[aria-label*="@"]');
                    if (emailElem) {
                        var val = emailElem.getAttribute('data-email') || emailElem.getAttribute('aria-label');
                        if (val && val.includes('@')) return val.trim();
                    }
                    if (document.title && !document.title.toLowerCase().includes('sign in') && !document.title.toLowerCase().includes('登录') && !document.title.includes('accounts.google.com')) {
                        return document.title.trim();
                    }
                } catch(e) {}
                return '';
            })();
            """
            webView.evaluateJavaScript(extractScript) { [weak self] result, _ in
                if let name = result as? String, !name.isEmpty {
                    let cleaned = ConnectionRecord.sanitizeAccountName(name)
                    DispatchQueue.main.async {
                        self?.parent.onAccountIdentified?(cleaned.isEmpty ? name : cleaned)
                    }
                }
            }
        }
        
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.viewModel.isLoading = false
                self.parent.viewModel.loadError = error.localizedDescription
                webView.scrollView.refreshControl?.endRefreshing()
                HapticManager.error()
            }
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.viewModel.isLoading = false
                webView.scrollView.refreshControl?.endRefreshing()
            }
        }
        
        // 处理 HTTP 证书与安全验证（允许局域网自签名证书）
        public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            
            // 如果是本地局域网或 localhost，放宽自签名 SSL 限制
            let host = challenge.protectionSpace.host
            if host == "localhost" || host == "127.0.0.1" || host.hasPrefix("192.168.") || host.hasPrefix("10.") {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
        
        // MARK: - WKUIDelegate
        
        // 处理 target="_blank" 新窗口，直接在当前 webView 加载
        public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        // 原生展示 JavaScript alert
        public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                completionHandler()
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(alert, animated: true)
            } else {
                completionHandler()
            }
        }
    }
}
