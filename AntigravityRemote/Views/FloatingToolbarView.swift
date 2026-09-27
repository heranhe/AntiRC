//
//  FloatingToolbarView.swift
//  AntigravityRemote
//
//  可自由拖拽、边缘吸附的半透明原生悬浮控制台
//

import SwiftUI

/// 悬浮控制器操作面板
public struct FloatingToolbarView: View {
    @ObservedObject public var webViewModel: WebViewModel
    @ObservedObject public var settings: AppSettings
    public var onDisconnect: () -> Void
    
    @State private var isExpanded: Bool = false
    @State private var showKeypad: Bool = false
    @State private var offset: CGSize = CGSize(width: 320, height: 600)
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var copiedNotice: Bool = false
    @State private var hasInitializedPosition: Bool = false
    
    public init(webViewModel: WebViewModel, settings: AppSettings, onDisconnect: @escaping () -> Void) {
        self.webViewModel = webViewModel
        self.settings = settings
        self.onDisconnect = onDisconnect
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            
            ZStack(alignment: .topLeading) {
                // 浮动按钮与菜单
                VStack(alignment: .trailing, spacing: 10) {
                    if isExpanded {
                        // 展开的操作面板
                        expandedMenuView
                            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                    
                    if showKeypad && isExpanded {
                        // 终端辅助键盘条
                        terminalKeypadView
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    
                    // 浮动主按钮（胶囊球）
                    mainFloatingButton
                }
                .opacity(isDragging ? 1.0 : (isExpanded ? 1.0 : 0.4))
                .offset(
                    x: min(max(16, offset.width + dragTranslation.width), screenSize.width - 68),
                    y: min(max(60, offset.height + dragTranslation.height), screenSize.height - 120)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragTranslation = value.translation
                        }
                        .onEnded { value in
                            isDragging = false
                            HapticManager.selection()
                            let finalX = offset.width + value.translation.width
                            let finalY = offset.height + value.translation.height
                            dragTranslation = .zero
                            
                            // 边缘吸附计算：吸附到左侧或右侧
                            let snapToRight = finalX > screenSize.width / 2
                            let targetX: CGFloat = snapToRight ? (screenSize.width - 68) : 16
                            let targetY = min(max(70, finalY), screenSize.height - 140)
                            
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                offset = CGSize(width: targetX, height: targetY)
                            }
                        }
                )
                .onAppear {
                    if !hasInitializedPosition {
                        // 初始默认停靠在右下角偏上位置，绝不挡住正中间的输入框或按钮
                        offset = CGSize(width: screenSize.width - 68, height: max(120, screenSize.height - 180))
                        hasInitializedPosition = true
                    }
                }
            }
        }
    }
    
    /// 浮动主触发按钮
    private var mainFloatingButton: some View {
        Button {
            HapticManager.medium()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
                if !isExpanded {
                    showKeypad = false
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(colors: [.blue.opacity(0.7), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    )
                
                Image(systemName: isExpanded ? "xmark" : "dot.scope")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.primary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
    }
    
    /// 展开的操作菜单
    private var expandedMenuView: some View {
        VStack(spacing: 8) {
            // 复制当前链接提示
            if copiedNotice {
                Text("已复制链接")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
            
            VStack(spacing: 6) {
                // 刷新
                menuActionButton(icon: "arrow.clockwise", label: "刷新") {
                    HapticManager.heavy()
                    webViewModel.reload()
                }
                
                // 网页后退
                menuActionButton(icon: "chevron.left", label: "后退", disabled: !webViewModel.canGoBack) {
                    HapticManager.light()
                    webViewModel.goBack()
                }
                
                // 终端快捷键面板开关
                menuActionButton(icon: "terminal.fill", label: "终端键", active: showKeypad) {
                    HapticManager.light()
                    withAnimation(.spring()) {
                        showKeypad.toggle()
                    }
                }
                
                // 灵动岛/全屏沉浸切换
                menuActionButton(
                    icon: settings.enableSafeAreas ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                    label: settings.enableSafeAreas ? "沉浸全屏" : "避让边距"
                ) {
                    HapticManager.medium()
                    withAnimation {
                        settings.enableSafeAreas.toggle()
                    }
                }
                
                // 复制链接
                menuActionButton(icon: "link", label: "复制链接") {
                    HapticManager.light()
                    if let urlString = webViewModel.currentURL?.absoluteString {
                        UIPasteboard.general.string = urlString
                        withAnimation {
                            copiedNotice = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copiedNotice = false }
                        }
                    }
                }
                
                // 暂时隐藏悬浮球
                menuActionButton(icon: "eye.slash", label: "隐藏悬浮球") {
                    HapticManager.light()
                    withAnimation {
                        isExpanded = false
                        settings.showFloatingButton = false
                    }
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                // 断开会话回到大厅
                menuActionButton(icon: "power", label: "断开连接", isDestructive: true) {
                    HapticManager.heavy()
                    onDisconnect()
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
    }
    
    /// 终端辅助键盘条（手机上操作 CLI 必备）
    private var terminalKeypadView: some View {
        HStack(spacing: 8) {
            terminalKeyButton(label: "Ctrl+C") {
                webViewModel.sendKey(key: "c", ctrl: true)
            }
            terminalKeyButton(label: "Esc") {
                webViewModel.sendKey(key: "Escape", ctrl: false)
            }
            terminalKeyButton(label: "Enter") {
                webViewModel.sendKey(key: "Enter", ctrl: false)
            }
            terminalKeyButton(label: "Tab") {
                webViewModel.sendKey(key: "Tab", ctrl: false)
            }
            terminalKeyButton(label: "↑") {
                webViewModel.sendKey(key: "ArrowUp", ctrl: false)
            }
            terminalKeyButton(label: "↓") {
                webViewModel.sendKey(key: "ArrowDown", ctrl: false)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(
                disabled ? .gray.opacity(0.5) :
                isDestructive ? .red :
                active ? .blue : .primary
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 100, alignment: .leading)
            .background(active ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .disabled(disabled)
    }
    
    private func terminalKeyButton(label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(6)
        }
    }
}
