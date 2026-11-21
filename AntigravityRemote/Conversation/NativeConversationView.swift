//
//  NativeConversationView.swift
//  AntigravityRemote
//
//  远程会话视图：全屏渲染网页版，保留顶部液态玻璃导航栏、原生账号切换与悬浮控制球
//

import SwiftUI
import WebKit

/// 远程会话视图
struct NativeConversationView: View {
    @ObservedObject var model: WebViewModel
    @ObservedObject var settings: AppSettings
    let title: String
    let userAgent: String
    let onAccountIdentified: (IdentifiedAccount) -> Void
    var onAcceptCurrentAccount: () -> Void = {}
    let onBack: () -> Void
    let onDisconnect: () -> Void

    @State private var showsAccountOptions = false
    @State private var showsSignOutConfirm = false
    @State private var webMenuUnavailable = false
    @State private var isSigningOut = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            // 全屏网页容器
            RemoteWebView(
                viewModel: model,
                userAgent: userAgent,
                onAccountIdentified: onAccountIdentified
            )
            .ignoresSafeArea(edges: settings.enableSafeAreas ? [] : .all)

            VStack(spacing: 0) {
                if let notice = model.accountNotice {
                    accountNoticeCard(notice)
                }
                // 当实例断开或加载失败时，置顶展示中文友好提示卡片
                if model.showsConnectionNotice {
                    disconnectedCard
                }
                Spacer()
            }
            .padding(.top, 8)

            if settings.showFloatingButton {
                FloatingToolbarView(webViewModel: model, settings: settings, onDisconnect: onDisconnect)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                navigation
                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(.accentColor)
                        .frame(height: 2)
                }
            }
            .background(.bar)
        }
        .animation(DesignToken.fade, value: model.isInstanceDisconnected)
        .animation(DesignToken.fade, value: model.loadError != nil)
        .animation(DesignToken.fade, value: model.accountNotice)
        .confirmationDialog("切换 Google 账号", isPresented: $showsAccountOptions, titleVisibility: .visible) {
            ForEach(settings.knownGoogleAccounts) { account in
                Button(accountLabel(account)) {
                    HapticManager.light()
                    model.selectAccount(index: account.index)
                }
            }
            Button("打开网页账号菜单") {
                model.openWebAccountMenu { found in
                    if !found { webMenuUnavailable = true }
                }
            }
            Button("添加其他 Google 账号") {
                model.addGoogleAccount()
            }
            Button("退出 App 内所有 Google 账号", role: .destructive) {
                showsSignOutConfirm = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(accountDialogMessage)
        }
        .alert("退出所有 Google 账号？", isPresented: $showsSignOutConfirm) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { signOutGoogle() }
        } message: {
            Text("只清除 App 内的 Google 登录状态，连接记录会保留。之后需要重新登录 Google。")
        }
        .alert("网页上暂时没有账号菜单", isPresented: $webMenuUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text(settings.knownGoogleAccounts.isEmpty
                 ? "页面还没显示 Google 头像（可能仍在加载或尚未登录）。请先在网页中登录，或选择“添加其他 Google 账号”。"
                 : "页面还没显示 Google 头像（可能仍在加载或尚未登录）。可以等页面加载完再试，或直接从列表选择账号。")
        }
    }

    private func accountLabel(_ account: KnownGoogleAccount) -> String {
        let name = account.email ?? "Google 账号 #\(account.index)"
        return account.index == model.currentSessionIndex ? "✓ \(name)" : name
    }

    private var accountDialogMessage: String {
        if let email = model.identifiedEmail {
            return "当前账号：\(email)。切换后会保留当前电脑和对话。"
        }
        return "尚未识别当前登录的账号。切换后会保留当前电脑和对话。"
    }

    private func signOutGoogle() {
        guard !isSigningOut else { return }
        isSigningOut = true
        HapticManager.heavy()
        settings.signOutGoogleAccounts {
            isSigningOut = false
            model.reloadWithoutAccount()
        }
    }

    // MARK: - 顶部导航栏
    // 只保留网页没有的：返回大厅、连接状态、账号与连接菜单。新建对话、刷新等交给网页自带的顶栏和输入框。
    private var navigation: some View {
        HStack(spacing: 8) {
            // 左侧：返回连接列表（后台保活，不掐断连接）
            glassButton("返回连接列表", symbol: "chevron.left", action: onBack)

            // 中间：标题与同步状态
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // 右侧：更多操作菜单
            moreMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - 更多操作菜单
    private var moreMenu: some View {
        Menu {
            Button {
                HapticManager.light()
                showsAccountOptions = true
            } label: {
                Label("切换 Google 账号", systemImage: "person.2.circle")
            }

            if model.canGoBack {
                Button {
                    HapticManager.light()
                    model.goBack()
                } label: {
                    Label("网页后退", systemImage: "chevron.backward")
                }
            }

            if !settings.showFloatingButton {
                Button {
                    settings.showFloatingButton = true
                } label: {
                    Label("显示悬浮控制球", systemImage: "dot.scope")
                }
            }

            if let url = model.currentURL {
                ShareLink(item: url) {
                    Label("分享连接", systemImage: "square.and.arrow.up")
                }
            }

            Divider()
            
            Button(role: .destructive, action: onDisconnect) {
                Label("断开连接", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .conversationGlass(in: Circle(), interactive: true)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多选项")
    }

    // MARK: - 账号差异提示
    private func accountNoticeCard(_ notice: AccountNotice) -> some View {
        let (title, detail, acceptLabel): (String, String, String) = {
            switch notice {
            case .mismatch(let expected, let current):
                return ("登录的账号变了",
                        "这台电脑上次使用 \(expected)，现在页面登录的是 \(current)。Google 退出某个账号后编号会重新排列，可能因此打开了另一个账号。",
                        "继续使用 \(current)")
            case .notRestored(let expectedIndex, let current):
                return ("没能恢复上次的账号",
                        "上次选择的是 Google 账号 #\(expectedIndex)，但页面打开的是 \(current)。该账号可能已在 App 内退出。",
                        "改用 \(current)")
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(DesignToken.fade) { model.accountNotice = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .accessibilityLabel("关闭提示")
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                noticeButton("切换账号", symbol: "person.2.circle", prominent: true) {
                    showsAccountOptions = true
                }
                noticeButton(acceptLabel, symbol: "checkmark", prominent: false) {
                    HapticManager.light()
                    onAcceptCurrentAccount()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.97))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func noticeButton(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(prominent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(prominent ? Color.accentColor : Color.primary)
        }
    }

    // MARK: - 断开连接中文提示卡片
    private var disconnectedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                Text(model.loadError != nil && !model.isInstanceDisconnected ? "页面加载失败" : "远程实例未连接")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(DesignToken.fade) {
                        model.dismissConnectionNotice()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .accessibilityLabel("关闭提示")
            }

            Text(disconnectedDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            HStack(spacing: 10) {
                noticeButton("重新连接", symbol: "arrow.clockwise", prominent: true) {
                    HapticManager.light()
                    model.reload()
                }
                noticeButton("切换 Google 账号", symbol: "person.2.circle", prominent: false) {
                    HapticManager.light()
                    showsAccountOptions = true
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.96))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var disconnectedDetail: String {
        if let error = model.loadError, !model.isInstanceDisconnected {
            return "网络或服务器暂时不可用：\(error)"
        }
        if model.accountWasGuessed, let index = model.currentSessionIndex {
            return "这台电脑是首次连接，App 暂时沿用了你最近使用的 Google 账号 #\(index)。如果电脑上登录的是其他账号，请切换账号。"
        }
        return RemoteWebView.disconnectedHint
    }

    private var statusText: String {
        switch model.health {
        case .failed: return "未连接"
        case .loading: return "正在加载…"
        case .signIn: return "等待登录 Google"
        case .ready:
            if model.conversationSupported || !model.projects.isEmpty { return "项目已同步" }
            return "已连接"
        }
    }

    private var statusColor: Color {
        switch model.health {
        case .failed: return .orange
        case .loading, .signIn: return .yellow
        case .ready: return .green
        }
    }

    private func glassButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .conversationGlass(in: Circle(), interactive: true)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - 玻璃质感修饰器
private struct ConversationGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.25), lineWidth: 1))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

private extension View {
    func conversationGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        modifier(ConversationGlass(shape: shape, interactive: interactive))
    }
}

#if DEBUG
@MainActor
func nativeConversationPreview() -> some View {
    let model = WebViewModel()
    let settings = AppSettings()
    return NativeConversationView(
        model: model,
        settings: settings,
        title: "我的 Mac 电脑",
        userAgent: "",
        onAccountIdentified: { _ in },
        onBack: {},
        onDisconnect: {}
    )
}

#Preview("远程网页会话") {
    nativeConversationPreview()
}
#endif
