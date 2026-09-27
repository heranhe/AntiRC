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
    }

    private func sessionShell(url: URL) -> some View {
        NativeConversationView(
            model: webViewModel,
            settings: settings,
            title: activeDeviceTitle,
            userAgent: settings.activeUserAgent,
            onAccountIdentified: { name in
                if let id = settings.activeAccountId {
                    settings.updateAccountInfo(id: id, accountName: name)
                }
            },
            onBack: returnToLobby,
            onDisconnect: disconnectSession
        )
    }

    private var activeDeviceTitle: String {
        if let id = settings.activeAccountId,
           let record = settings.historyList.first(where: { $0.id == id }) {
            return record.displayName
        }
        return "远程会话"
    }

    // MARK: - Lifecycle

    private func connectToSession(url: URL) {
        // 如果已有活跃连接，且连接目标是同一个 URL：瞬间直接切回会话界面，无需重新握手加载
        if case .connected(let existingURL) = sessionState, existingURL == url {
            if let id = settings.activeAccountId {
                settings.updateAccountStatus(id: id, status: .connected)
            }
            withAnimation(DesignToken.fade) {
                isShowingConversation = true
            }
            return
        }

        // 新建连接或切换不同设备
        webViewModel.currentURL = url
        webViewModel.loadError = nil
        webViewModel.resetConversation()

        if let id = settings.activeAccountId {
            settings.updateAccountStatus(id: id, status: .connected)
        }

        sessionState = .connected(url: url)
        withAnimation(DesignToken.fade) {
            isShowingConversation = true
        }
    }

    /// 返回连接大厅（将会话保持在后台存活，不销毁连接，大厅保持绿色在线状态）
    private func returnToLobby() {
        withAnimation(DesignToken.fade) {
            isShowingConversation = false
        }
    }

    /// 彻底断开连接（终止后台会话，释放资源，大厅状态切为已断开）
    private func disconnectSession() {
        if let id = settings.activeAccountId {
            settings.updateAccountStatus(id: id, status: .disconnected)
        }
        withAnimation(DesignToken.fade) {
            isShowingConversation = false
            sessionState = .disconnected
        }
        webViewModel.resetConversation()
    }
}
