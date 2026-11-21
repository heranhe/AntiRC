//
//  MainContainerView.swift
//  AntigravityRemote
//
//  主容器：连接大厅 ↔ SwiftUI 原生对话
//

import SwiftUI
import PhotosUI

public enum SessionState: Equatable {
    case disconnected
    case connected(url: URL)
}

/// A clearly identified, offline walkthrough for reviewers and new users.
/// No Google session, remote computer, or model service is contacted.
struct DemoConversationView: View {
    let onClose: () -> Void

    @State private var messages = [
        ConversationMessage(id: "demo-welcome", role: "assistant", text: "欢迎体验 Antigravity Remote。这里展示原生对话界面；演示消息和用量均为本机示例数据。连接自己的电脑后，才能发送真实任务。")
    ]
    @State private var draft = ""
    @State private var selectedModel = "Gemini 3.8 Flash"
    @State private var showsModels = false
    @State private var showsUsage = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoError: String?

    private let models = ["Gemini 3.8 Flash", "Gemini 3.8 Pro", "Claude Sonnet 4.5"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                demoBanner
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }
                        .padding(18)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let id = messages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                composer
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("演示对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回连接") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("用量") { showsUsage = true }
                }
            }
            .sheet(isPresented: $showsModels) { modelSheet }
            .sheet(isPresented: $showsUsage) { usageSheet }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    defer { selectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              UIImage(data: data) != nil else {
                            photoError = "无法读取这张图片"
                            return
                        }
                        photoData = data
                        photoError = nil
                    } catch {
                        photoError = "读取图片失败，请重试"
                    }
                }
            }
        }
        .accessibilityIdentifier("demoConversation")
    }

    private var demoBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
            Text("免登录演示 · 内容保存在本机，不会发送给 AI 或远程电脑。真实功能请返回并连接自己的 Antigravity。")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.13))
        .accessibilityIdentifier("demoDisclosure")
    }

    private func messageRow(_ message: ConversationMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == "user" ? "你" : "演示助手")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(message.role == "user" ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20))
            if message.role != "user" { Spacer(minLength: 44) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = photoData, let image = UIImage(data: data) {
                HStack(spacing: 10) {
                    Image(uiImage: image)
                        .resizable().scaledToFill().frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("图片预览 · 仅本机演示")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("移除") { photoData = nil }
                }
            }
            if let photoError { Text(photoError).font(.caption).foregroundStyle(.orange) }
            TextField("输入一条演示消息", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("demoComposer")
            HStack(spacing: 8) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("图片", systemImage: "photo")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("demoPhotoPicker")
                Button {
                    showsModels = true
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedModel).lineLimit(1)
                        Image(systemName: "chevron.up").font(.caption2)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("demoModelPicker")
                Spacer(minLength: 4)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoData == nil)
                .accessibilityLabel("发送演示消息")
                .accessibilityIdentifier("demoSend")
            }
            .font(.subheadline)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(12)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = photoData != nil
        let content = [text, attached ? "[已添加一张演示图片]" : nil]
            .compactMap { $0 }.joined(separator: "\n")
        guard !content.isEmpty else { return }
        messages.append(ConversationMessage(role: "user", text: content))
        messages.append(ConversationMessage(role: "assistant", text:
            "已展示消息发送流程。当前选用 \(selectedModel)。这是一条本机预设回复；连接 Antigravity 后才会生成真实回答。"))
        draft = ""
        photoData = nil
    }

    private var modelSheet: some View {
        NavigationStack {
            List(models, id: \.self) { model in
                Button {
                    selectedModel = model
                    showsModels = false
                } label: {
                    HStack {
                        Text(model)
                        Spacer()
                        if selectedModel == model { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("模型演示")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text("以下为界面示例；可用模型以真实连接为准。")
                    .font(.footnote).foregroundStyle(.secondary).padding()
            }
        }
        .presentationDetents([.medium])
    }

    private var usageSheet: some View {
        NavigationStack {
            List {
                Section("示例用量") {
                    usageRow("Gemini 3.8 Flash", remaining: 72)
                    usageRow("Gemini 3.8 Pro", remaining: 41)
                    usageRow("Claude Sonnet 4.5", remaining: 86)
                }
                Section {
                    Text("这些百分比仅用于演示页面布局，不代表你的账户实际用量。连接远程会话后查看真实数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("用量演示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showsUsage = false } } }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("demoUsage")
    }

    private func usageRow(_ name: String, remaining: Int) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text("剩余 \(remaining)%")
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(minHeight: 42)
    }
}

public struct MainContainerView: View {
    @ObservedObject public var settings: AppSettings

    @State private var sessionState: SessionState = .disconnected
    @State private var isShowingConversation: Bool = false
    /// 当前网页会话对应的连接记录。
    @State private var sessionRecordID: UUID?
    /// 推测账号尚未确认期间识别到的邮箱，确认可用后再写入记录。
    @State private var pendingIdentifiedEmail: String?
    @StateObject private var webViewModel = WebViewModel()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        ZStack {
            DesignToken.screenBG.ignoresSafeArea()

            // 连接大厅：常驻底层，未显示会话时可正常交互
            ConnectView(settings: settings) { target in
                if let url = URL(string: target) {
                    connectToSession(url: url)
                }
            }
            .opacity(isShowingConversation ? 0 : 1)
            .allowsHitTesting(!isShowingConversation)

            // 远程会话视图：连接建立后常驻在 ZStack 中保活，返回大厅时仅隐藏，不销毁 WKWebView，实现 0 秒瞬间重入
            if case .connected(let url) = sessionState {
                sessionShell(url: url)
                    .opacity(isShowingConversation ? 1 : 0)
                    .offset(y: isShowingConversation ? 0 : 25)
                    .allowsHitTesting(isShowingConversation)
            }
        }
        .animation(DesignToken.fade, value: isShowingConversation)
        .preferredColorScheme(isShowingConversation ? nil : .dark)
        .onChange(of: webViewModel.health) { _, health in
            syncSessionStatus(health)
        }
        .onChange(of: workspaceConfirmed) { _, confirmed in
            if confirmed { confirmGuessedAccount() }
        }
        .onChange(of: settings.webSessionResetToken) { _, _ in
            // 网页数据已清除，旧会话的登录态不再可信。
            if case .connected = sessionState { disconnectSession() }
        }
        .onChange(of: settings.historyList.map(\.id)) { _, ids in
            // 当前会话的记录被删除或清空后，账户选择已无处保存，直接结束会话。
            if let sessionRecordID, !ids.contains(sessionRecordID), case .connected = sessionState {
                disconnectSession()
            }
        }
    }

    private func sessionShell(url: URL) -> some View {
        NativeConversationView(
            model: webViewModel,
            settings: settings,
            title: activeDeviceTitle,
            userAgent: settings.activeUserAgent,
            onAccountIdentified: handleIdentifiedAccount,
            onAcceptCurrentAccount: acceptCurrentAccount,
            onBack: returnToLobby,
            onDisconnect: disconnectSession
        )
    }

    private var activeDeviceTitle: String {
        if let id = sessionRecordID,
           let record = settings.historyList.first(where: { $0.id == id }) {
            return record.displayName
        }
        return "远程会话"
    }

    /// 对话或项目列表成功同步，说明当前账号确实能访问这台电脑。
    private var workspaceConfirmed: Bool {
        webViewModel.conversationSupported || !webViewModel.projects.isEmpty
    }

    // MARK: - Lifecycle

    private func connectToSession(url: URL) {
        let effectiveURL = url
        let recordID = settings.activeAccountId

        // 如果已有活跃连接，且连接目标是同一台设备的同一 URL：瞬间直接切回会话界面，无需重新握手加载
        if case .connected(let existingURL) = sessionState, existingURL == effectiveURL, recordID == sessionRecordID {
            syncSessionStatus(webViewModel.health)
            withAnimation(DesignToken.fade) {
                isShowingConversation = true
            }
            return
        }

        // 新建连接或切换不同设备
        let model = webViewModel
        webViewModel.onAccountRouteChanged = { [weak settings] url, recordID in
            // 推测的账号还没被证明可用，先不把它写成这台电脑的偏好。
            guard !model.accountWasGuessed else { return }
            settings?.recordAccountRoute(url, for: recordID)
        }
        webViewModel.onAccountSelected = { [weak settings] url, recordID in
            settings?.selectAccountRoute(url, for: recordID)
        }
        sessionRecordID = recordID
        pendingIdentifiedEmail = nil
        webViewModel.resetConversation()
        webViewModel.loadError = nil
        webViewModel.health = .loading
        webViewModel.load(effectiveURL, connectionID: recordID,
                          guessedAccount: settings.lastPreparedAccountSource == .guessed)

        if let recordID {
            settings.updateSessionStatus(id: recordID, status: .connecting)
        }

        sessionState = .connected(url: effectiveURL)
        withAnimation(DesignToken.fade) {
            isShowingConversation = true
        }
    }

    /// 大厅里的“已连接”只反映网页真实状态：加载中/待登录为连接中，失败或实例断开为未连接。
    private func syncSessionStatus(_ health: SessionHealth) {
        guard let id = sessionRecordID, case .connected = sessionState else { return }
        let status: ConnectionStatus
        switch health {
        case .ready: status = .connected
        case .failed: status = .disconnected
        case .loading, .signIn: status = .connecting
        }
        settings.updateSessionStatus(id: id, status: status)
    }

    private func handleIdentifiedAccount(_ account: IdentifiedAccount) {
        guard let id = account.connectionID ?? sessionRecordID else { return }
        if webViewModel.accountWasGuessed {
            pendingIdentifiedEmail = account.email
            return
        }
        if !account.matchesPreference {
            // 纠正重试后仍落在别的编号：不覆盖偏好，请用户决定。
            if let expected = settings.historyList.first(where: { $0.id == id })?.googleSessionIndex {
                webViewModel.accountNotice = .notRestored(expectedIndex: expected, current: account.email)
            }
            return
        }
        switch settings.recordIdentifiedAccount(account.email, for: id) {
        case .recorded:
            if case .mismatch = webViewModel.accountNotice { webViewModel.accountNotice = nil }
        case .mismatch(let expected):
            webViewModel.accountNotice = .mismatch(expected: expected, current: account.email)
        }
    }

    /// 用户确认以当前页面账号为准。
    private func acceptCurrentAccount() {
        guard let id = sessionRecordID, let notice = webViewModel.accountNotice else { return }
        switch notice {
        case .mismatch(_, let current):
            settings.recordSuccessfulLogin(account: current, for: id)
        case .notRestored(_, let current):
            if let url = webViewModel.currentURL {
                settings.adoptCurrentAccount(url: url, email: current, for: id)
            }
            webViewModel.adoptCurrentAccount()
        }
        webViewModel.accountNotice = nil
    }

    /// 推测的账号成功同步到对话或项目后，才保存为这台电脑的偏好。
    private func confirmGuessedAccount() {
        guard webViewModel.accountWasGuessed, let id = sessionRecordID else { return }
        webViewModel.accountWasGuessed = false
        if let url = webViewModel.currentURL {
            settings.recordAccountRoute(url, for: id)
        }
        if let email = pendingIdentifiedEmail {
            _ = settings.recordIdentifiedAccount(email, for: id)
            pendingIdentifiedEmail = nil
        }
    }

    /// 返回连接大厅（将会话保持在后台存活，不销毁连接，大厅保持在线状态）
    private func returnToLobby() {
        withAnimation(DesignToken.fade) {
            isShowingConversation = false
        }
    }

    /// 彻底断开连接（终止后台会话，释放资源，大厅状态切为未连接）
    private func disconnectSession() {
        if let id = sessionRecordID {
            settings.updateSessionStatus(id: id, status: .disconnected)
        }
        withAnimation(DesignToken.fade) {
            isShowingConversation = false
            sessionState = .disconnected
        }
        sessionRecordID = nil
        pendingIdentifiedEmail = nil
        webViewModel.resetConversation()
        webViewModel.accountNotice = nil
        webViewModel.accountWasGuessed = false
    }
}
