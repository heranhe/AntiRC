//
//  HapticManager.swift
//  AntigravityRemote
//
//  原生 Taptic Engine 触觉震动反馈工具
//

import UIKit

/// 触觉震动管理器
public enum HapticManager {
    /// 触发轻度触觉撞击（适合普通按钮点击、键盘按压）
    public static func light() {
        guard AppSettings.shared.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// 触发中度触觉撞击（适合模式切换、展开菜单）
    public static func medium() {
        guard AppSettings.shared.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// 触发硬朗触觉撞击（适合确认操作、下拉刷新触发）
    public static func heavy() {
        guard AppSettings.shared.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// 触发成功通知震动（适合连接成功、扫码识别完成）
    public static func success() {
        guard AppSettings.shared.hapticsEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
    
    /// 触发警告或失败通知震动（适合连接失败、无效地址）
    public static func error() {
        guard AppSettings.shared.hapticsEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
    
    /// 触发选择器轮盘滚动感（适合拖动吸附、选项切换）
    public static func selection() {
        guard AppSettings.shared.hapticsEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
