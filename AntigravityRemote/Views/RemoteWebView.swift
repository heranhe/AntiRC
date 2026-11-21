//
//  RemoteWebView.swift
//  AntigravityRemote
//
//  核心 WKWebView 封装，深度适配灵动岛、安全区，注入防拦截 UA，并支持下拉刷新与侧滑
//

import SwiftUI
import WebKit

public struct WebLoadRequest: Equatable {
    public let id = UUID()
    public let url: URL
    public let connectionID: UUID?
    /// 账户编号沿用自其他电脑（推测值）：不强制纠正，也不阻止页面落到其他账号。
    public var guessedAccount = false
}

/// 网页会话的实际健康状态，用于大厅的“已连接”标记与顶部状态文字。
public enum SessionHealth: Equatable {
    case loading
    case ready
    case signIn
    case failed
}

/// 页面头像识别出的账号。
public struct IdentifiedAccount: Equatable {
    public let email: String
    public let pageURL: URL?
    public let connectionID: UUID?
    /// 当前页面的会话编号是否就是应用期望恢复的编号。
    public let matchesPreference: Bool
}

/// 需要用户确认的账号差异。
public enum AccountNotice: Equatable {
    /// 同一编号下的邮箱换了人（通常是 Google 退出某账号后编号重排）。
    case mismatch(expected: String, current: String)
    /// 没能恢复上次选择的编号，页面落到了另一个账号。
    case notRestored(expectedIndex: String, current: String)
}

/// 网页控制器状态与动作载体
public final class WebViewModel: ObservableObject {
    @Published public var currentURL: URL?
    @Published public private(set) var loadRequest: WebLoadRequest?
    var onAccountRouteChanged: ((URL, UUID) -> Void)?
    var onAccountSelected: ((URL, UUID) -> Void)?

    public func load(_ url: URL, connectionID: UUID?, guessedAccount: Bool = false) {
        currentURL = url
        accountWasGuessed = guessedAccount
        accountNotice = nil
        identifiedEmail = nil
        loadRequest = WebLoadRequest(url: url, connectionID: connectionID, guessedAccount: guessedAccount)
    }
    @Published public var pageTitle: String = ""
    @Published public var progress: Double = 0.0
    @Published public var isLoading: Bool = false
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var loadError: String? = nil
    @Published public var isInstanceDisconnected: Bool = false
    @Published public var lastDisconnectedNotice: String? = nil
    @Published public var health: SessionHealth = .loading
    /// 本次连接使用的是其他电脑的账户编号。
    @Published public var accountWasGuessed = false
    @Published public var accountNotice: AccountNotice?
    /// 页面头像显示的邮箱（尚未登录或未识别时为 nil）。
    @Published public var identifiedEmail: String?
    @Published private(set) var connectionNoticeDismissed = false
    var showsConnectionNotice: Bool {
        !connectionNoticeDismissed && (loadError != nil || isInstanceDisconnected)
    }

    /// 当前页面所用的 Google 会话编号；无编号即 Google 默认账号。
    var currentSessionIndex: String? {
        guard let currentURL, AntigravityAccountRoute.isRemotePage(currentURL) else { return nil }
        return AntigravityAccountRoute.sessionIndex(in: currentURL) ?? "0"
    }

    func dismissConnectionNotice() {
        connectionNoticeDismissed = true
    }

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
    var newConversationAction: ((String?) -> Void)?
    var openWebAccountMenuAction: ((@escaping (Bool) -> Void) -> Void)?
    var selectAccountIndexAction: ((String) -> Void)?
    var addAccountAction: (() -> Void)?
    var reloadWithoutAccountAction: (() -> Void)?
    var adoptCurrentAccountAction: (() -> Void)?

    func resetConversation(resetNotice: Bool = true) {
        if resetNotice { connectionNoticeDismissed = false }
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
        isInstanceDisconnected = false
        lastDisconnectedNotice = nil
    }

    /// 点击网页右上角的 Google 头像，打开网页自带的账号菜单。completion 返回是否找到头像。
    public func openWebAccountMenu(completion: @escaping (Bool) -> Void = { _ in }) {
        dismissConnectionNotice()
        guard let openWebAccountMenuAction else { completion(false); return }
        openWebAccountMenuAction(completion)
    }

    /// 兼容旧调用：直接打开网页账号菜单。
    public func openAccountChooser() {
        openWebAccountMenu()
    }

    /// 以指定会话编号重新打开当前实例与会话。
    public func selectAccount(index: String) {
        dismissConnectionNotice()
        accountNotice = nil
        identifiedEmail = nil
        accountWasGuessed = false
        selectAccountIndexAction?(index)
    }

    /// 打开 Google 的“添加账号”页面，完成后回到当前实例。
    public func addGoogleAccount() {
        dismissConnectionNotice()
        accountNotice = nil
        addAccountAction?()
    }

    /// 退出 Google 后以无账号编号的地址重新打开实例，由网页引导重新登录。
    public func reloadWithoutAccount() {
        accountNotice = nil
        accountWasGuessed = false
        reloadWithoutAccountAction?()
    }

    /// 用户确认“以当前页面账号为准”后，网页层也改用当前编号。
    public func adoptCurrentAccount() {
        accountNotice = nil
        accountWasGuessed = false
        adoptCurrentAccountAction?()
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
    public func newConversation(projectTitle: String? = nil) { newConversationAction?(projectTitle) }

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
        self.loadRequest = initialURL.map { WebLoadRequest(url: $0, connectionID: nil) }
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
    public var onAccountIdentified: ((IdentifiedAccount) -> Void)?

    public init(viewModel: WebViewModel, userAgent: String, onAccountIdentified: ((IdentifiedAccount) -> Void)? = nil) {
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

        config.userContentController.add(context.coordinator, name: "googleAccount")
        config.userContentController.addUserScript(WKUserScript(
            source: GoogleAccountBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false
        ))

        config.userContentController.add(context.coordinator, name: "conversation")
        config.userContentController.add(context.coordinator, name: "instanceStatus")
        config.userContentController.addUserScript(WKUserScript(
            source: ConversationBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false
        ))
        config.userContentController.addUserScript(WKUserScript(
            source: InstanceStatusBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false
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
        if let request = viewModel.loadRequest {
            context.coordinator.load(request, in: webView)
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
        if let request = viewModel.loadRequest,
           request.id != context.coordinator.loadedRequestID {
            context.coordinator.load(request, in: uiView)
        }
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "googleAccount")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "conversation")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "instanceStatus")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    static let disconnectedHint = "请确认电脑端已登录同一个 Google 账号，并且 Antigravity 正在运行。"

    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var loadedRequestID: UUID?
        private var loadedConnectionID: UUID?
        private var awaitingCommit = true
        private var lastDiagnosticRoute: String?
        private var connectionURL: URL?
        private var preferredSessionIndex: String?
        private var attemptedAccountRecovery = false
        /// 用户在 Google 登录/账号页面中主动操作过（点链接、提交表单、打开弹窗）。
        /// 回到远程页面时，落地账号即为用户的新选择，不再被旧偏好拉回。
        private(set) var userAccountFlow = false

        func load(_ request: WebLoadRequest, in webView: WKWebView) {
            loadedRequestID = request.id
            loadedConnectionID = request.connectionID
            awaitingCommit = true
            lastDiagnosticRoute = nil
            let target = AntigravityAccountRoute.remoteDestination(in: request.url) ?? request.url
            connectionURL = target
            preferredSessionIndex = AntigravityAccountRoute.sessionIndex(in: target)
            // 推测的编号不做纠正重试：新电脑可能本就属于其他账号。
            attemptedAccountRecovery = request.guessedAccount
            userAccountFlow = false
            AccountDiagnostics.shared.record(.loadRequested, url: target)
            webView.load(URLRequest(url: target, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        }

        private func recordCurrentRoute(in webView: WKWebView) {
            guard !awaitingCommit, let url = webView.url, let connectionID = loadedConnectionID else { return }
            let summary = AccountDiagnostics.routeSummary(url)
            if summary != lastDiagnosticRoute {
                lastDiagnosticRoute = summary
                AccountDiagnostics.shared.record(.routeObserved, url: url)
            }
            parent.viewModel.onAccountRouteChanged?(url, connectionID)
            if preferredSessionIndex == nil {
                preferredSessionIndex = AntigravityAccountRoute.sessionIndex(in: url)
            }
        }

        /// Preserve the instance/conversation while switching via Google's account menu.
        func selectAccount(_ index: String, in webView: WKWebView) {
            guard AccountDiagnostics.safeIndex(index) == index,
                  let connectionURL, AntigravityAccountRoute.isRemotePage(connectionURL),
                  let connectionID = loadedConnectionID else { return }
            let target = AntigravityAccountRoute.applying(index, to: connectionURL)
            preferredSessionIndex = index
            attemptedAccountRecovery = false
            userAccountFlow = false
            parent.viewModel.onAccountSelected?(target, connectionID)
            parent.viewModel.dismissConnectionNotice()
            parent.viewModel.accountWasGuessed = false
            parent.viewModel.accountNotice = nil
            AccountDiagnostics.shared.record(.accountSelected, url: target)
            awaitingCommit = true
            webView.load(URLRequest(url: target))
        }

        /// 用户主动的 Google 账号流程结束、回到远程页面：接受落地的账号作为新选择。
        private func acceptAccountFlowLanding(_ url: URL) {
            userAccountFlow = false
            attemptedAccountRecovery = true
            let index = AntigravityAccountRoute.sessionIndex(in: url) ?? "0"
            guard index != preferredSessionIndex else { return }
            preferredSessionIndex = index
            parent.viewModel.accountWasGuessed = false
            if let connectionID = loadedConnectionID {
                parent.viewModel.onAccountSelected?(AntigravityAccountRoute.applying(index, to: url), connectionID)
            }
            AccountDiagnostics.shared.record(.accountSelected, url: url)
        }

        /// 统一识别 Google 账号菜单生成的 ?authuser=N 远程链接（点击或新窗口打开均可）。
        private func menuSelectionIndex(for url: URL?) -> String? {
            guard let url, AntigravityAccountRoute.isRemotePage(url),
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "authuser" }) == true
            else { return nil }
            return AntigravityAccountRoute.requestedSessionIndex(in: url)
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "googleAccount" {
                guard let sourceURL = message.frameInfo.request.url,
                      sourceURL.scheme == "https",
                      let host = sourceURL.host?.lowercased(),
                      host == "antigravity.google.com" || host == "ogs.google.com" else { return }
                if let event = message.body as? [String: String], event["event"] == "accountSelected",
                   let index = event["index"], let webView {
                    selectAccount(index, in: webView)
                    return
                }
                guard message.frameInfo.isMainFrame else { return }
                if let event = message.body as? [String: String], event["event"] == "accountChooserOpened" {
                    AccountDiagnostics.shared.record(.chooserOpened, url: message.frameInfo.request.url)
                    parent.viewModel.dismissConnectionNotice()
                    return
                }
                guard let value = message.body as? String,
                      let email = UserAgentHelper.extractEmail(from: value) else { return }
                let currentURL = webView?.url
                var matches = true
                if let preferredSessionIndex, let currentURL, AntigravityAccountRoute.isRemotePage(currentURL) {
                    matches = (AntigravityAccountRoute.sessionIndex(in: currentURL) ?? "0") == preferredSessionIndex
                }
                AccountDiagnostics.shared.record(.profileDetected, url: message.frameInfo.request.url)
                parent.viewModel.identifiedEmail = email
                parent.onAccountIdentified?(IdentifiedAccount(
                    email: email, pageURL: currentURL, connectionID: loadedConnectionID, matchesPreference: matches
                ))
                return
            }
            if message.name == "instanceStatus" {
                guard let body = message.body as? [String: Any], let status = body["status"] as? String else { return }
                DispatchQueue.main.async {
                    let model = self.parent.viewModel
                    if status == "disconnected" {
                        model.isInstanceDisconnected = true
                        model.lastDisconnectedNotice = RemoteWebView.disconnectedHint
                        model.health = .failed
                    } else if status == "connected", model.isInstanceDisconnected {
                        model.isInstanceDisconnected = false
                        model.lastDisconnectedNotice = nil
                        if model.loadError == nil { model.health = .ready }
                    }
                }
                return
            }

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
        private var urlObservation: NSKeyValueObservation?
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
            urlObservation?.invalidate()
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
            parent.viewModel.newConversationAction = { [weak self] project in
                self?.perform("newConversation", value: project ?? "")
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

            parent.viewModel.sendKeyAction = { [weak self, weak webView] key, ctrl in
                // 向当前对话所在 frame 的焦点元素派发键盘事件（终端快捷键如 Ctrl+C、Enter、Esc）。
                let code = key.count == 1 ? "Key" + key.uppercased() : key
                webView?.callAsyncJavaScript("""
                    const active = document.activeElement || document.body;
                    for (const type of ['keydown', 'keyup']) {
                      active.dispatchEvent(new KeyboardEvent(type, {
                        key, code, ctrlKey: ctrl, bubbles: true, cancelable: true, composed: true
                      }));
                    }
                    return true;
                    """, arguments: ["key": key, "code": code, "ctrl": ctrl], in: self?.activeFrame, in: .page) { _ in }
            }

            parent.viewModel.openWebAccountMenuAction = { [weak webView] completion in
                guard let webView else { completion(false); return }
                webView.callAsyncJavaScript("""
                    const label = /Google\\s*(Account|账号|帳號|账户)/i;
                    const candidates = [
                      ...document.querySelectorAll('a[aria-label], button[aria-label], [role="button"][aria-label]')
                    ].filter(el => label.test(el.getAttribute('aria-label') || '') && el.getClientRects().length);
                    const fallback = document.querySelector('a[href*="accounts.google.com/SignOutOptions"]')
                      || document.querySelector('#gb img[src*="googleusercontent.com"]')?.closest('a, button, [role="button"]');
                    const target = candidates[0] || fallback;
                    if (!target) return false;
                    target.click();
                    return true;
                    """, arguments: [:], in: nil, in: .page) { result in
                    if case .success(let value) = result { completion((value as? Bool) == true) }
                    else { completion(false) }
                }
            }

            parent.viewModel.selectAccountIndexAction = { [weak self, weak webView] index in
                guard let self, let webView else { return }
                self.selectAccount(index, in: webView)
            }

            parent.viewModel.addAccountAction = { [weak self, weak webView] in
                guard let self, let webView, let connectionURL = self.connectionURL else { return }
                var components = URLComponents(string: "https://accounts.google.com/AddSession")!
                let landing = AntigravityAccountRoute.removingSessionIndex(from: connectionURL)
                components.queryItems = [URLQueryItem(name: "continue", value: landing.absoluteString)]
                guard let url = components.url else { return }
                self.userAccountFlow = true
                self.awaitingCommit = true
                webView.load(URLRequest(url: url))
            }

            parent.viewModel.reloadWithoutAccountAction = { [weak self, weak webView] in
                guard let self, let webView, let connectionURL = self.connectionURL else { return }
                let landing = AntigravityAccountRoute.removingSessionIndex(from: connectionURL)
                self.preferredSessionIndex = nil
                self.attemptedAccountRecovery = true
                // 退出后网页会引导重新登录，登录后落地的账号即为新的选择。
                self.userAccountFlow = true
                self.awaitingCommit = true
                webView.load(URLRequest(url: landing))
            }

            parent.viewModel.adoptCurrentAccountAction = { [weak self, weak webView] in
                guard let self, let url = webView?.url, AntigravityAccountRoute.isRemotePage(url) else { return }
                self.preferredSessionIndex = AntigravityAccountRoute.sessionIndex(in: url) ?? "0"
                self.attemptedAccountRecovery = true
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
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                // KVO 也会在网页调用 History API 切换账户路径时触发。
                // URL 展示变化不再被 updateUIView 当作新的加载命令。
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.recordCurrentRoute(in: view)
                    self.parent.viewModel.currentURL = view.url
                }
            }
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

        private func openExternally(_ url: URL) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }

        // MARK: - WKNavigationDelegate

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            AccountDiagnostics.shared.record(.navigationAction, url: url, code: navigationAction.navigationType.rawValue)
            let userInitiated = navigationAction.navigationType == .linkActivated
                || navigationAction.navigationType == .formSubmitted

            // 非网页协议（mailto:、tel: 等）与无关站点交给系统处理，避免远程会话页被替换。
            if userInitiated, !UserAgentHelper.shouldOpenInApp(url, connectionHost: connectionURL?.host) {
                decisionHandler(.cancel)
                openExternally(url)
                return
            }
            if GoogleSignInGate.isAccountLogin(url), userInitiated {
                userAccountFlow = true
            }
            if AntigravityAccountRoute.isRemotePage(url) {
                // 账号菜单可能以点击、重定向或新窗口方式到达，统一保留当前实例和会话。
                if let selectedIndex = menuSelectionIndex(for: url) {
                    decisionHandler(.cancel)
                    selectAccount(selectedIndex, in: webView)
                    return
                }
                // In-page links often omit /u/N/. Keep the chosen account on those links.
                if navigationAction.navigationType == .linkActivated,
                   AntigravityAccountRoute.sessionIndex(in: url) == nil,
                   let preferredSessionIndex {
                    decisionHandler(.cancel)
                    awaitingCommit = true
                    webView.load(URLRequest(url: AntigravityAccountRoute.applying(preferredSessionIndex, to: url)))
                    return
                }
            }
            decisionHandler(.allow)
        }

        public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            AccountDiagnostics.shared.record(.redirect, url: webView.url)
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            AccountDiagnostics.shared.record(.provisional, url: webView.url)
            awaitingCommit = true
            activeFrame = nil
            activeFrameID = nil
            activeFramePriority = 0
            DispatchQueue.main.async {
                self.parent.viewModel.resetConversation(resetNotice: false)
                self.parent.viewModel.isLoading = true
                self.parent.viewModel.loadError = nil
                self.parent.viewModel.isInstanceDisconnected = false
                self.parent.viewModel.health = .loading
            }
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            AccountDiagnostics.shared.record(.committed, url: webView.url)
            awaitingCommit = false
            if let url = webView.url, AntigravityAccountRoute.isRemotePage(url) {
                if userAccountFlow {
                    acceptAccountFlowLanding(url)
                } else if let preferredSessionIndex,
                          (AntigravityAccountRoute.sessionIndex(in: url) ?? "0") != preferredSessionIndex,
                          !attemptedAccountRecovery {
                    // One bounded retry handles a restored page landing on the bare/default route.
                    attemptedAccountRecovery = true
                    awaitingCommit = true
                    let target = AntigravityAccountRoute.applying(preferredSessionIndex, to: url)
                    AccountDiagnostics.shared.record(.accountRecovery, url: target)
                    webView.load(URLRequest(url: target))
                    return
                }
            }
            recordCurrentRoute(in: webView)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AccountDiagnostics.shared.record(.finished, url: webView.url)
            recordCurrentRoute(in: webView)
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

            let onSignInPage = webView.url.map(GoogleSignInGate.isAccountLogin) ?? false
            DispatchQueue.main.async {
                self.parent.viewModel.isLoading = false
                webView.scrollView.refreshControl?.endRefreshing()
                if let url = webView.url {
                    self.parent.viewModel.currentURL = url
                }
                if !self.parent.viewModel.isInstanceDisconnected {
                    self.parent.viewModel.health = onSignInPage ? .signIn : .ready
                }
            }

            // 检查实例断开状态；账户由持续观察头像的 GoogleAccountBridge 独立识别。
            let extractScript = """
            (function() {
                try {
                    var bodyText = document.body ? (document.body.innerText || '') : '';
                    return bodyText.includes('Instance disconnected') ||
                           bodyText.includes('This instance is no longer connected') ||
                           bodyText.includes('远程实例未连接或已断开');
                } catch(e) {}
                return false;
            })();
            """
            webView.evaluateJavaScript(extractScript) { [weak self] result, _ in
                guard let self, (result as? Bool) == true else { return }
                DispatchQueue.main.async {
                    self.parent.viewModel.isInstanceDisconnected = true
                    self.parent.viewModel.lastDisconnectedNotice = RemoteWebView.disconnectedHint
                    self.parent.viewModel.health = .failed
                }
            }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            AccountDiagnostics.shared.record(.provisionalFailed, url: webView.url, code: (error as NSError).code)
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async {
                self.parent.viewModel.isLoading = false
                self.parent.viewModel.loadError = error.localizedDescription
                self.parent.viewModel.health = .failed
                webView.scrollView.refreshControl?.endRefreshing()
                HapticManager.error()
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AccountDiagnostics.shared.record(.navigationFailed, url: webView.url, code: (error as NSError).code)
            DispatchQueue.main.async {
                self.parent.viewModel.isLoading = false
                webView.scrollView.refreshControl?.endRefreshing()
            }
        }

        /// 系统在后台回收网页进程后会留下白屏；回到前台时重新加载当前页面。
        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            AccountDiagnostics.shared.record(.navigationFailed, url: webView.url, code: -1)
            if webView.url != nil {
                webView.reload()
            } else if let connectionURL {
                awaitingCommit = true
                let target = preferredSessionIndex.map { AntigravityAccountRoute.applying($0, to: connectionURL) } ?? connectionURL
                webView.load(URLRequest(url: target))
            }
        }

        // 处理 HTTP 证书与安全验证（允许局域网自签名证书）
        public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            // 如果是本地局域网或 localhost，放宽自签名 SSL 限制
            if UserAgentHelper.isLocalNetworkHost(challenge.protectionSpace.host) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        // MARK: - WKUIDelegate

        // 处理 target="_blank" 新窗口：账号菜单与 Google 登录在当前 webView 内完成，其他站点交给系统浏览器
        public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }
            AccountDiagnostics.shared.record(.popup, url: url)
            if let selectedIndex = menuSelectionIndex(for: url) {
                selectAccount(selectedIndex, in: webView)
                return nil
            }
            guard UserAgentHelper.shouldOpenInApp(url, connectionHost: connectionURL?.host) else {
                openExternally(url)
                return nil
            }
            if GoogleSignInGate.isAccountLogin(url) {
                // 新窗口只能由用户手势打开：添加账号、退出、管理账号等都属于主动操作。
                userAccountFlow = true
            }
            webView.load(navigationAction.request)
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
                var presenter = rootVC
                while let next = presenter.presentedViewController { presenter = next }
                presenter.present(alert, animated: true)
            } else {
                completionHandler()
            }
        }
    }
}
