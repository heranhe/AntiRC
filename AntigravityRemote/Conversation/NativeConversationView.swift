//
//  NativeConversationView.swift
//  AntigravityRemote
//
//  远程会话视图：全屏渲染网页版，保留顶部液态玻璃导航栏并支持右上角字号调节
//

import SwiftUI
import WebKit

/// 远程会话视图
struct NativeConversationView: View {
    @ObservedObject var model: WebViewModel
    @ObservedObject var settings: AppSettings
    let title: String
    let userAgent: String
    let onAccountIdentified: (String) -> Void
    let onBack: () -> Void
    let onDisconnect: () -> Void

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
    }

    // MARK: - 顶部导航栏（保留顶部 UI）
    private var navigation: some View {
        HStack(spacing: 12) {
            // 左侧：返回连接列表（后台保活，不掐断连接）
            glassButton("返回连接列表", symbol: "chevron.left", action: onBack)
            
            // 中间：标题与同步状态
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            // 网页后退（如有历史页面）
            if model.canGoBack {
                Button {
                    HapticManager.light()
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .conversationGlass(in: Circle(), interactive: true)
                }
                .accessibilityLabel("网页后退")
            }
            
            // 右侧：更多操作菜单
            moreMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .systemBackground).opacity(0.85),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }
    
    // MARK: - 更多操作菜单
    private var moreMenu: some View {
        Menu {
            Button {
                HapticManager.light()
                model.reload()
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
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
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .conversationGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel("更多选项")
    }

    private var statusText: String {
        if model.loadError != nil { return "连接失败" }
        if model.isLoading { return "正在加载…" }
        if model.conversationSupported { return "项目已同步" }
        if !model.projects.isEmpty { return "项目已同步" }
        return "已连接"
    }

    private var statusColor: Color {
        if model.loadError != nil { return .orange }
        if model.isLoading { return .yellow }
        return .green
    }

    private func glassButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .conversationGlass(in: Circle(), interactive: true)
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
