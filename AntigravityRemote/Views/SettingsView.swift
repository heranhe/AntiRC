//
//  SettingsView.swift
//  AntigravityRemote
//
//  应用偏好设置与内核配置页面
//

import SwiftUI

/// 偏好设置页面
public struct SettingsView: View {
    @ObservedObject public var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingClearCacheSuccess = false
    @State private var showingClearCacheAlert = false
    
    public init(settings: AppSettings) {
        self.settings = settings
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // 运行体验
                Section(header: Text("运行体验")) {
                    Toggle(isOn: $settings.preventSleep) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("保持屏幕常亮")
                                .font(.body)
                            Text("防止长任务、代码生成或监控过程中手机自动锁屏断连")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $settings.hapticsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Taptic Engine 触觉反馈")
                                .font(.body)
                            Text("在扫码成功、刷新页面、按键操作时提供震动反馈")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $settings.showFloatingButton) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示悬浮辅助控制球")
                                .font(.body)
                            Text("在网页顶层提供快捷刷新/返回/终端键；若觉得遮挡可在此关闭")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $settings.autoFillClipboard) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("启动时智能检测剪贴板")
                                .font(.body)
                            Text("如果剪贴板内有网址，打开 App 自动提示一键连接")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $settings.showNewbieHelpTips) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示电脑端扫码步骤")
                                .font(.body)
                            Text("在主页底部展示如何打开电脑端设置与开启扫码的说明卡片")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 屏幕与灵动岛适配
                Section(header: Text("屏幕与灵动岛适配")) {
                    Toggle(isOn: $settings.enableSafeAreas) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("避让灵动岛与屏幕边缘")
                                .font(.body)
                            Text("开启后保护顶部状态栏与底部手势条；关闭后进入全屏沉浸模式")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // User-Agent 兼容性
                Section(
                    header: Text("浏览器内核与登录兼容 (User-Agent)"),
                    footer: Text("Google 账号登录会交给系统 Safari 完成，和手机 Safari 共用登录状态，因此不会再卡在蓝牙验证。这里的 User-Agent 只影响其他网页。")
                ) {
                    Picker("User-Agent 预设", selection: $settings.userAgentPreset) {
                        ForEach(UserAgentPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    
                    if settings.userAgentPreset == .custom {
                        TextField("输入自定义 User-Agent 字符串", text: $settings.customUserAgent)
                            .font(.system(size: 13, design: .monospaced))
                    }
                }
                
                // 缓存与数据维护
                Section(header: Text("缓存与状态重置")) {
                    Button {
                        HapticManager.light()
                        settings.resetOnboarding()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("重新查看开屏引导页")
                        }
                    }

                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("清除网页缓存与登录 Cookie")
                        }
                    }
                }
                
                // 关于信息
                Section(header: Text("关于")) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                            
                            Text("AntiRC")
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                        Spacer()
                    }
                    
                    HStack {
                        Text("应用名称")
                        Spacer()
                        Text("AntiRC")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("内核架构")
                        Spacer()
                        Text("SwiftUI + WebKit 纯原生")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("偏好设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("确认清除缓存？", isPresented: $showingClearCacheAlert) {
                Button("取消", role: .cancel) { }
                Button("确定清除", role: .destructive) {
                    HapticManager.heavy()
                    settings.clearWebCache {
                        showingClearCacheSuccess = true
                    }
                }
            } message: {
                Text("此操作将清空 WebKit 的所有本地缓存、LocalStorage 和登录凭证。")
            }
            .alert("清除成功", isPresented: $showingClearCacheSuccess) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("已成功清理网页本地数据，下次访问将重新加载最新资源。")
            }
        }
    }
}
