//
//  AppSettings.swift
//  AntigravityRemote
//
//  应用全局设置与偏好管理，支持持久化存储与屏幕防休眠
//

import SwiftUI
import Combine
import WebKit

/// 预设的 User-Agent 选项
public enum UserAgentPreset: String, CaseIterable, Identifiable {
    case standardSafari = "标准 Mobile Safari (推荐防拦截)"
    case desktopSafari = "桌面版 Safari (大屏模式)"
    case custom = "自定义 User-Agent"
    
    public var id: String { rawValue }
    
    public var userAgentString: String {
        switch self {
        case .standardSafari:
            return UserAgentHelper.mobileSafariUserAgent()
        case .desktopSafari:
            // 桌面版 Safari，以获得完整桌面布局
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
        case .custom:
            return ""
        }
    }
}

/// 应用设置管理中心
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let historyStorageKey = "Antigravity_Connection_History"
    private let preventSleepKey = "Antigravity_Prevent_Sleep"
    private let hapticsKey = "Antigravity_Haptics_Enabled"
    private let safeAreaKey = "Antigravity_Enable_Safe_Areas"
    private let clipboardKey = "Antigravity_Auto_Clipboard"
    private let userAgentPresetKey = "Antigravity_UA_Preset"
    private let customUAKey = "Antigravity_Custom_UA"
    private let floatingButtonKey = "Antigravity_Show_Floating_Button"
    private let onboardingKey = "Antigravity_Has_Completed_Onboarding"
    private let newbieHelpKey = "Antigravity_Show_Newbie_Help"
    
    /// 是否在网页顶层显示悬浮控制球
    @Published public var showFloatingButton: Bool {
        didSet {
            UserDefaults.standard.set(showFloatingButton, forKey: floatingButtonKey)
        }
    }
    
    /// 是否防止屏幕自动息屏休眠
    @Published public var preventSleep: Bool {
        didSet {
            UserDefaults.standard.set(preventSleep, forKey: preventSleepKey)
            updateIdleTimer()
        }
    }
    
    /// 是否开启触觉震动反馈
    @Published public var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: hapticsKey)
        }
    }
    
    /// 是否避让安全区（为 false 时进入全面屏沉浸）
    @Published public var enableSafeAreas: Bool {
        didSet {
            UserDefaults.standard.set(enableSafeAreas, forKey: safeAreaKey)
        }
    }
    
    /// 是否启动时自动识别剪贴板 URL
    @Published public var autoFillClipboard: Bool {
        didSet {
            UserDefaults.standard.set(autoFillClipboard, forKey: clipboardKey)
        }
    }
    
    /// User-Agent 预设类型
    @Published public var userAgentPreset: UserAgentPreset {
        didSet {
            UserDefaults.standard.set(userAgentPreset.rawValue, forKey: userAgentPresetKey)
        }
    }
    
    /// 自定义 User-Agent 内容
    @Published public var customUserAgent: String {
        didSet {
            UserDefaults.standard.set(customUserAgent, forKey: customUAKey)
        }
    }

    /// 是否已完成首次开屏引导
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }

    /// 是否显示电脑端扫码步骤指引卡片
    @Published public var showNewbieHelpTips: Bool {
        didSet {
            UserDefaults.standard.set(showNewbieHelpTips, forKey: newbieHelpKey)
        }
    }
    
    /// 历史连接与账户列表
    @Published public var historyList: [ConnectionRecord] = []
    
    /// 当前活跃或上次连接的账户 ID
    @Published public var activeAccountId: UUID? = nil
    
    public init() {
        // 读取首次引导状态，默认为 false
        let savedOnboarding = UserDefaults.standard.object(forKey: onboardingKey) as? Bool ?? false
        self.hasCompletedOnboarding = savedOnboarding

        // 读取扫码步骤卡片设置，默认为 true，用户可随时关闭
        let savedNewbieHelp = UserDefaults.standard.object(forKey: newbieHelpKey) as? Bool ?? true
        self.showNewbieHelpTips = savedNewbieHelp

        // 读取悬浮控制球设置，默认开启（但位置贴边且支持关闭）
        let savedFloatingButton = UserDefaults.standard.object(forKey: floatingButtonKey) as? Bool ?? true
        self.showFloatingButton = savedFloatingButton
        
        // 读取防休眠设置，默认开启以避免长任务中断
        let savedPreventSleep = UserDefaults.standard.object(forKey: preventSleepKey) as? Bool ?? true
        self.preventSleep = savedPreventSleep

        // 读取触觉反馈设置，默认开启
        let savedHaptics = UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true
        self.hapticsEnabled = savedHaptics
        
        // 读取安全区设置，默认开启避让
        let savedSafeArea = UserDefaults.standard.object(forKey: safeAreaKey) as? Bool ?? true
        self.enableSafeAreas = savedSafeArea
        
        // 剪贴板自动识别，默认开启
        let savedClipboard = UserDefaults.standard.object(forKey: clipboardKey) as? Bool ?? true
        self.autoFillClipboard = savedClipboard
        
        // User-Agent 预设，默认标准 Safari
        if let savedPresetRaw = UserDefaults.standard.string(forKey: userAgentPresetKey),
           let preset = UserAgentPreset(rawValue: savedPresetRaw) {
            self.userAgentPreset = preset
        } else {
            self.userAgentPreset = .standardSafari
        }
        
        // 自定义 UA
        self.customUserAgent = UserDefaults.standard.string(forKey: customUAKey) ?? ""
        
        // 加载历史记录
        loadHistory()
        
        // 初始防休眠状态同步
        updateIdleTimer()
    }
    
    /// 获取当前生效的 User-Agent 字符串
    public var activeUserAgent: String {
        switch userAgentPreset {
        case .standardSafari:
            return UserAgentPreset.standardSafari.userAgentString
        case .desktopSafari:
            return UserAgentPreset.desktopSafari.userAgentString
        case .custom:
            return customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? UserAgentPreset.standardSafari.userAgentString
                : customUserAgent
        }
    }
    
    /// 更新系统防息屏设置
    public func updateIdleTimer() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = self.preventSleep
        }
    }
    
    /// 添加或更新连接与账户记录
    @discardableResult
    public func saveConnection(
        urlString: String,
        deviceAlias: String? = nil,
        accountName: String? = nil,
        status: ConnectionStatus? = nil
    ) -> ConnectionRecord {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return ConnectionRecord(urlString: urlString)
        }
        
        var record: ConnectionRecord
        if let index = historyList.firstIndex(where: { $0.urlString == trimmedURL }) {
            record = historyList[index]
            record.lastUsedAt = Date()
            if let status = status {
                record.status = status
            }
            if let alias = deviceAlias, !alias.isEmpty {
                record.deviceAlias = alias
            }
            if let account = accountName, !account.isEmpty {
                record.accountName = account
            }
            historyList.remove(at: index)
            historyList.insert(record, at: 0)
        } else {
            record = ConnectionRecord(
                deviceAlias: deviceAlias,
                accountName: accountName,
                status: status ?? .connecting,
                urlString: trimmedURL,
                createdAt: Date(),
                lastUsedAt: Date()
            )
            historyList.insert(record, at: 0)
        }
        
        self.activeAccountId = record.id
        persistHistory()
        return record
    }
    
    /// 更新账户在线状态
    public func updateAccountStatus(id: UUID, status: ConnectionStatus) {
        if let index = historyList.firstIndex(where: { $0.id == id }) {
            historyList[index].status = status
            if status == .connected {
                historyList[index].lastUsedAt = Date()
            }
            persistHistory()
        }
    }
    
    /// 将所有处于已登录状态的账户重置为已断开
    public func disconnectAllAccounts() {
        for index in historyList.indices {
            historyList[index].status = .disconnected
        }
        persistHistory()
    }
    
    /// 更新账户名称与备注别名
    public func updateAccountInfo(id: UUID, accountName: String? = nil, alias: String? = nil) {
        if let index = historyList.firstIndex(where: { $0.id == id }) {
            if let acc = accountName, !acc.isEmpty {
                historyList[index].accountName = ConnectionRecord.sanitizeAccountName(acc)
            }
            if let al = alias {
                historyList[index].deviceAlias = al.isEmpty ? nil : al
            }
            persistHistory()
        }
    }
    
    /// 删除某条连接记录
    public func removeConnection(at offsets: IndexSet) {
        historyList.remove(atOffsets: offsets)
        persistHistory()
    }
    
    /// 删除特定连接记录
    public func removeConnection(id: UUID) {
        historyList.removeAll { $0.id == id }
        persistHistory()
    }
    
    /// 清空所有历史记录
    public func clearAllHistory() {
        historyList.removeAll()
        persistHistory()
    }
    
    /// 从持久化中读取历史记录
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyStorageKey) else { return }
        do {
            var decoded = try JSONDecoder().decode([ConnectionRecord].self, from: data)
            for i in decoded.indices {
                if let acc = decoded[i].accountName {
                    decoded[i].accountName = ConnectionRecord.sanitizeAccountName(acc)
                }
            }
            self.historyList = decoded
        } catch {
            print("读取连接历史失败: \(error)")
        }
    }
    
    /// 持久化历史记录
    private func persistHistory() {
        do {
            let encoded = try JSONEncoder().encode(historyList)
            UserDefaults.standard.set(encoded, forKey: historyStorageKey)
        } catch {
            print("保存连接历史失败: \(error)")
        }
    }
    
    /// 一键清除所有 WebKit 网页缓存和 Cookies
    public func clearWebCache(completion: (() -> Void)? = nil) {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    /// 重置首次开屏引导
    public func resetOnboarding() {
        self.hasCompletedOnboarding = false
    }

    /// 完成开屏引导
    public func completeOnboarding() {
        self.hasCompletedOnboarding = true
    }
}
