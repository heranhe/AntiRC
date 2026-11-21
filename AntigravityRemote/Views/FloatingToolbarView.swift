//
//  FloatingToolbarView.swift
//  AntigravityRemote
//
//  可自由拖拽、边缘吸附的半透明原生悬浮控制球；展开的操作面板固定在屏幕底部，不会被挤出屏幕
//

import SwiftUI

/// 悬浮控制器操作面板
public struct FloatingToolbarView: View {
    @ObservedObject public var webViewModel: WebViewModel
    @ObservedObject public var settings: AppSettings
    public var onDisconnect: () -> Void

    @State private var isExpanded = false
    @State private var showKeypad = false
    /// 控制球中心点；nil 表示尚未根据屏幕尺寸初始化。
    @State private var center: CGPoint?
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false
    @State private var copiedNotice = false

    private let ballSize: CGFloat = 50
    private let edgeInset: CGFloat = 12

    public init(webViewModel: WebViewModel, settings: AppSettings, onDisconnect: @escaping () -> Void) {
        self.webViewModel = webViewModel
        self.settings = settings
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if isExpanded {
                    // 点击空白处收起面板
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { collapse() }

                    VStack(spacing: 10) {
                        Spacer()
                        if copiedNotice {
                            Text("已复制链接")
                                .font(.caption2.bold())
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        if showKeypad {
                            terminalKeypadView
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        actionPanel
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, ballSize + 28)
                    .transition(.opacity)
                }

                mainFloatingButton
                    .position(clampedCenter(in: size))
                    .gesture(dragGesture(in: size))
                    .onAppear {
                        if center == nil {
                            // 默认停靠在右下方，避开底部输入框与 Home 指示条
                            center = CGPoint(x: size.width - edgeInset - ballSize / 2, y: size.height * 0.62)
                        }
                    }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func clampedCenter(in size: CGSize) -> CGPoint {
        let base = center ?? CGPoint(x: size.width - edgeInset - ballSize / 2, y: size.height * 0.62)
        let half = ballSize / 2
        return CGPoint(
            x: min(max(half + edgeInset, base.x + dragTranslation.width), size.width - half - edgeInset),
            y: min(max(half + 8, base.y + dragTranslation.height), size.height - half - 8)
        )
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                isDragging = true
                dragTranslation = value.translation
            }
            .onEnded { _ in
                let current = clampedCenter(in: size)
                dragTranslation = .zero
                isDragging = false
                HapticManager.selection()
                // 边缘吸附：吸附到左侧或右侧
                let snapX = current.x > size.width / 2
                    ? size.width - edgeInset - ballSize / 2
                    : edgeInset + ballSize / 2
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    center = CGPoint(x: snapX, y: current.y)
                }
            }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isExpanded = false
            showKeypad = false
        }
    }

    /// 浮动主触发按钮
    private var mainFloatingButton: some View {
        Button {
            HapticManager.medium()
            if isExpanded { collapse() } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isExpanded = true }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: ballSize, height: ballSize)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(colors: [.blue.opacity(0.7), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    )
                Image(systemName: isExpanded ? "xmark" : "dot.scope")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.primary)
            }
            .opacity(isDragging || isExpanded ? 1 : 0.55)
        }
        .accessibilityLabel(isExpanded ? "收起控制面板" : "打开控制面板")
    }

    /// 展开的操作面板（横向滚动，适配窄屏）
    private var actionPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                menuActionButton(icon: "arrow.clockwise", label: "刷新") {
                    HapticManager.heavy()
                    webViewModel.reload()
                }
                menuActionButton(icon: "chevron.left", label: "后退", disabled: !webViewModel.canGoBack) {
                    HapticManager.light()
                    webViewModel.goBack()
                }
                menuActionButton(icon: "terminal.fill", label: "终端键", active: showKeypad) {
                    HapticManager.light()
                    withAnimation(.spring()) { showKeypad.toggle() }
                }
                menuActionButton(
                    icon: settings.enableSafeAreas ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                    label: settings.enableSafeAreas ? "沉浸全屏" : "避让边距"
                ) {
                    HapticManager.medium()
                    withAnimation { settings.enableSafeAreas.toggle() }
                }
                menuActionButton(icon: "link", label: "复制链接", disabled: webViewModel.currentURL == nil) {
                    HapticManager.light()
                    guard let urlString = webViewModel.currentURL?.absoluteString else { return }
                    UIPasteboard.general.string = urlString
                    withAnimation { copiedNotice = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copiedNotice = false }
                    }
                }
                menuActionButton(icon: "eye.slash", label: "隐藏") {
                    HapticManager.light()
                    collapse()
                    settings.showFloatingButton = false
                }
                menuActionButton(icon: "power", label: "断开", isDestructive: true) {
                    HapticManager.heavy()
                    collapse()
                    onDisconnect()
                }
            }
            .padding(8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
    }

    /// 终端辅助键盘条（手机上操作 CLI 必备）
    private var terminalKeypadView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                terminalKeyButton(label: "Ctrl+C") { webViewModel.sendKey(key: "c", ctrl: true) }
                terminalKeyButton(label: "Esc") { webViewModel.sendKey(key: "Escape") }
                terminalKeyButton(label: "Enter") { webViewModel.sendKey(key: "Enter") }
                terminalKeyButton(label: "Tab") { webViewModel.sendKey(key: "Tab") }
                terminalKeyButton(label: "↑") { webViewModel.sendKey(key: "ArrowUp") }
                terminalKeyButton(label: "↓") { webViewModel.sendKey(key: "ArrowDown") }
            }
            .padding(8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private func menuActionButton(
        icon: String,
        label: String,
        disabled: Bool = false,
        active: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(
                disabled ? .gray.opacity(0.5) :
                isDestructive ? .red :
                active ? .blue : .primary
            )
            .frame(minWidth: 56, minHeight: 48)
            .background(active ? Color.blue.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(disabled)
    }

    private func terminalKeyButton(label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
