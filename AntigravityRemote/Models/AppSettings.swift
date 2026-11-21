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

/// 首次请求所用账户编号的来源。
public enum AccountRouteSource: Equatable {
    case none, explicitLink, saved, guessed
}

/// 页面头像邮箱与记录比对的结果。
public enum IdentifiedAccountResult: Equatable {
    case recorded
    case mismatch(expected: String)
}

/// 本机 Google 会话编号与最近识别到的邮箱。
public struct KnownGoogleAccount: Hashable, Identifiable {
    public let index: String
    public let email: String?
    public var id: String { index }
}

/// 应用设置管理中心
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let defaults: UserDefaults
    private let lastGoogleSessionIndexKey = "Antigravity_Last_Google_Session_Index"
    private var lastGoogleSessionIndex: String? {
        get { defaults.string(forKey: lastGoogleSessionIndexKey) }
        set { defaults.set(newValue, forKey: lastGoogleSessionIndexKey) }
    }

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
    /// 旧版本写入但从未读取的邮箱缓存；启动时删除，避免无用的个人信息留在偏好中。
    private let legacyAccountKeys = ["Antigravity_Last_Logged_In_Account", "Antigravity_Last_Logged_In_Email"]
    private let activeAccountIdKey = "Antigravity_Active_Account_Id"

    /// 最近一次 prepareConnection 采用的账户编号来源。
    /// `.guessed` 表示沿用其他电脑的编号，只用于首次请求，不写入记录。
    @Published public private(set) var lastPreparedAccountSource: AccountRouteSource = .none

    /// 清除网页数据后递增，通知正在运行的会话断开。
    @Published public private(set) var webSessionResetToken = 0

    /// 是否在网页顶层显示悬浮控制球
    @Published public var showFloatingButton: Bool {
        didSet {
            defaults.set(showFloatingButton, forKey: floatingButtonKey)
        }
    }
    
    /// 是否防止屏幕自动息屏休眠
    @Published public var preventSleep: Bool {
        didSet {
            defaults.set(preventSleep, forKey: preventSleepKey)
            updateIdleTimer()
        }
    }
    
    /// 是否开启触觉震动反馈
    @Published public var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: hapticsKey)
        }
    }
    
    /// 是否避让安全区（为 false 时进入全面屏沉浸）
    @Published public var enableSafeAreas: Bool {
        didSet {
            defaults.set(enableSafeAreas, forKey: safeAreaKey)
        }
    }
    
    /// 是否启动时自动识别剪贴板 URL
    @Published public var autoFillClipboard: Bool {
        didSet {
            defaults.set(autoFillClipboard, forKey: clipboardKey)
        }
    }
    
    /// User-Agent 预设类型
    @Published public var userAgentPreset: UserAgentPreset {
        didSet {
            defaults.set(userAgentPreset.rawValue, forKey: userAgentPresetKey)
        }
    }
    
    /// 自定义 User-Agent 内容
    @Published public var customUserAgent: String {
        didSet {
            defaults.set(customUserAgent, forKey: customUAKey)
        }
    }

    /// 是否已完成首次开屏引导
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }

    /// 是否显示电脑端扫码步骤指引卡片
    @Published public var showNewbieHelpTips: Bool {
        didSet {
            defaults.set(showNewbieHelpTips, forKey: newbieHelpKey)
        }
    }
    
    /// 历史连接与账户列表
    @Published public var historyList: [ConnectionRecord] = []
    
    /// 当前活跃或上次连接的账户 ID
    @Published public var activeAccountId: UUID? = nil {
        didSet {
            defaults.set(activeAccountId?.uuidString, forKey: activeAccountIdKey)
        }
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        legacyAccountKeys.forEach { defaults.removeObject(forKey: $0) }
        if let idStr = defaults.string(forKey: activeAccountIdKey),
           let uuid = UUID(uuidString: idStr) {
            self.activeAccountId = uuid
        }

        // 读取首次引导状态，默认为 false
        let savedOnboarding = defaults.object(forKey: onboardingKey) as? Bool ?? false
        self.hasCompletedOnboarding = savedOnboarding

        // 读取扫码步骤卡片设置，默认为 true，用户可随时关闭
        let savedNewbieHelp = defaults.object(forKey: newbieHelpKey) as? Bool ?? true
        self.showNewbieHelpTips = savedNewbieHelp

        // 读取悬浮控制球设置，默认开启（但位置贴边且支持关闭）
        let savedFloatingButton = defaults.object(forKey: floatingButtonKey) as? Bool ?? true
        self.showFloatingButton = savedFloatingButton
        
        // 读取防休眠设置，默认开启以避免长任务中断
        let savedPreventSleep = defaults.object(forKey: preventSleepKey) as? Bool ?? true
        self.preventSleep = savedPreventSleep

        // 读取触觉反馈设置，默认开启
        let savedHaptics = defaults.object(forKey: hapticsKey) as? Bool ?? true
        self.hapticsEnabled = savedHaptics
        
        // 读取安全区设置，默认开启避让
        let savedSafeArea = defaults.object(forKey: safeAreaKey) as? Bool ?? true
        self.enableSafeAreas = savedSafeArea
        
        // 剪贴板自动识别，默认开启
        let savedClipboard = defaults.object(forKey: clipboardKey) as? Bool ?? true
        self.autoFillClipboard = savedClipboard
        
        // User-Agent 预设，默认标准 Safari
        if let savedPresetRaw = defaults.string(forKey: userAgentPresetKey),
           let preset = UserAgentPreset(rawValue: savedPresetRaw) {
            self.userAgentPreset = preset
        } else {
            self.userAgentPreset = .standardSafari
        }
        
        // 自定义 UA
        self.customUserAgent = defaults.string(forKey: customUAKey) ?? ""
        
        // 加载历史记录。进程刚启动时没有任何存活的网页会话，旧的“已连接”状态一律作废。
        loadHistory()
        resetStaleStatuses()
        AccountDiagnostics.shared.record(.settingsRestored, selectedIndex: lastGoogleSessionIndex)
        
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
                record.accountName = ConnectionRecord.sanitizeAccountName(account)
            }
            historyList.remove(at: index)
            historyList.insert(record, at: 0)
        } else {
            record = ConnectionRecord(
                deviceAlias: deviceAlias,
                accountName: accountName.map(ConnectionRecord.sanitizeAccountName),
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
    
    /// 无条件记录页面头像对应的邮箱（用户确认后，或尚无期望邮箱时使用）。
    public func recordSuccessfulLogin(account: String, for recordId: UUID? = nil) {
        guard let email = UserAgentHelper.extractEmail(from: account),
              let targetId = recordId ?? activeAccountId,
              let index = historyList.firstIndex(where: { $0.id == targetId }) else { return }
        historyList[index].accountName = email
        persistHistory()
    }

    /// 页面识别到头像邮箱后调用。Google 退出某个账号后会重排 /u/N/ 编号，
    /// 同一编号可能已换成另一个人，因此已有邮箱与识别结果不同时交给用户确认，不静默覆盖。
    public func recordIdentifiedAccount(_ account: String, for recordID: UUID) -> IdentifiedAccountResult {
        guard let email = UserAgentHelper.extractEmail(from: account),
              let index = historyList.firstIndex(where: { $0.id == recordID }) else { return .recorded }
        if let expected = historyList[index].accountName.flatMap(UserAgentHelper.extractEmail(from:)) {
            return expected.caseInsensitiveCompare(email) == .orderedSame ? .recorded : .mismatch(expected: expected)
        }
        historyList[index].accountName = email
        persistHistory()
        return .recorded
    }

    /// 用户确认“以当前页面账号为准”：保存当前页面的会话编号（无编号即默认账号 0）和邮箱。
    public func adoptCurrentAccount(url: URL, email: String?, for recordID: UUID) {
        guard AntigravityAccountRoute.isRemotePage(url) else { return }
        let index = AntigravityAccountRoute.sessionIndex(in: url) ?? "0"
        selectAccountRoute(AntigravityAccountRoute.applying(index, to: url), for: recordID)
        if let email { recordSuccessfulLogin(account: email, for: recordID) }
    }

    /// 本机见过的 Google 会话编号及其最近一次识别到的邮箱，供原生账号切换菜单使用。
    public var knownGoogleAccounts: [KnownGoogleAccount] {
        var emails: [String: String?] = [:]
        for record in historyList {
            guard let index = record.googleSessionIndex else { continue }
            let email = record.accountName.flatMap(UserAgentHelper.extractEmail(from:))
            if let existing = emails[index], existing != nil { continue }
            emails[index] = email
        }
        return emails
            .map { KnownGoogleAccount(index: $0.key, email: $0.value) }
            .sorted { (Int($0.index) ?? 0) < (Int($1.index) ?? 0) }
    }

    /// 所有连接入口共用此方法，先恢复账户路径，再生成第一次网页请求。
    public func prepareConnection(urlString: String, recordID: UUID? = nil) -> URL? {
        guard UserAgentHelper.isValidRemoteURL(urlString),
              let inputURL = URL(string: UserAgentHelper.normalizeRemoteURL(urlString)) else { return nil }
        let key = AntigravityAccountRoute.connectionKey(for: inputURL)
        let existing = recordID.flatMap { id in historyList.first { $0.id == id } }
            ?? historyList.first { record in
                guard let url = URL(string: record.urlString) else { return false }
                return AntigravityAccountRoute.connectionKey(for: url) == key
            }
        let savedIndex = existing?.googleSessionIndex
        let explicitIndex = AntigravityAccountRoute.requestedSessionIndex(in: inputURL)
        let index: String?
        let source: AccountRouteSource
        if recordID != nil, let savedIndex {
            (index, source) = (savedIndex, .saved)
        } else if let explicitIndex {
            (index, source) = (explicitIndex, .explicitLink)
        } else if let savedIndex {
            (index, source) = (savedIndex, .saved)
        } else if let lastGoogleSessionIndex {
            // 新电脑没有自己的偏好时，先试最近使用的账号；它可能属于其他账号，所以不写入记录。
            (index, source) = (lastGoogleSessionIndex, .guessed)
        } else {
            (index, source) = (nil, .none)
        }
        lastPreparedAccountSource = source
        let target = AntigravityAccountRoute.applying(index, to: inputURL)
        AccountDiagnostics.shared.record(.prepareInput, url: inputURL, selectedIndex: savedIndex ?? lastGoogleSessionIndex)
        AccountDiagnostics.shared.record(.prepareTarget, url: target, selectedIndex: index)
        if let existing, let position = historyList.firstIndex(where: { $0.id == existing.id }) {
            var record = historyList.remove(at: position)
            record.lastUsedAt = Date()
            record.status = .connecting
            historyList.insert(record, at: 0)
            activeAccountId = record.id
            persistHistory()
        } else {
            saveConnection(urlString: inputURL.absoluteString, status: .connecting)
        }
        if source == .explicitLink || source == .saved, let activeAccountId {
            selectAccountRoute(target, for: activeAccountId)
        }
        return target
    }

    /// 页面结果只能补齐尚未建立的偏好，不能覆盖用户已经选择的账户。
    public func recordAccountRoute(_ url: URL, for recordID: UUID) {
        guard let record = historyList.first(where: { $0.id == recordID }),
              record.googleSessionIndex == nil else { return }
        selectAccountRoute(url, for: recordID)
    }

    /// 用户主动选择账户时立即持久化，不等待 Google 的弹窗或重定向完成。
    public func selectAccountRoute(_ url: URL, for recordID: UUID) {
        guard let sessionIndex = AntigravityAccountRoute.sessionIndex(in: url),
              let index = historyList.firstIndex(where: { $0.id == recordID }),
              let originalURL = URL(string: historyList[index].urlString),
              let destination = AntigravityAccountRoute.remoteDestination(in: originalURL) else { return }
        let migrated = originalURL != destination
        if migrated {
            historyList[index].urlString = destination.absoluteString
        }
        lastGoogleSessionIndex = sessionIndex
        guard historyList[index].googleSessionIndex != sessionIndex else {
            if migrated { persistHistory() }
            return
        }
        AccountDiagnostics.shared.record(.routeSaved, url: url, selectedIndex: historyList[index].googleSessionIndex)
        historyList[index].googleSessionIndex = sessionIndex
        // 账户编号变化后，旧邮箱标签暂时不再代表当前账户。
        historyList[index].accountName = nil
        persistHistory()
    }

    /// 更新当前会话状态。同一时间只有一个网页会话，其余记录一律标为未连接。
    public func updateSessionStatus(id: UUID, status: ConnectionStatus) {
        var changed = false
        for index in historyList.indices {
            let next: ConnectionStatus = historyList[index].id == id ? status : .disconnected
            if historyList[index].status != next {
                historyList[index].status = next
                changed = true
            }
            if historyList[index].id == id, status == .connected {
                historyList[index].lastUsedAt = Date()
                changed = true
            }
        }
        if changed { persistHistory() }
    }

    private func resetStaleStatuses() {
        guard historyList.contains(where: { $0.status != .disconnected }) else { return }
        for index in historyList.indices { historyList[index].status = .disconnected }
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
        guard let data = defaults.data(forKey: historyStorageKey) else { return }
        do {
            var decoded = try JSONDecoder().decode([ConnectionRecord].self, from: data)
            var migrated = false
            for i in decoded.indices {
                if let oldURL = URL(string: decoded[i].urlString),
                   let destination = AntigravityAccountRoute.remoteDestination(in: oldURL), destination != oldURL {
                    decoded[i].urlString = destination.absoluteString
                    migrated = true
                }
                if decoded[i].googleSessionIndex == nil, let url = URL(string: decoded[i].urlString) {
                    decoded[i].googleSessionIndex = AntigravityAccountRoute.sessionIndex(in: url)
                }
                if let acc = decoded[i].accountName {
                    decoded[i].accountName = ConnectionRecord.sanitizeAccountName(acc)
                }
            }
            self.historyList = decoded
            if migrated { persistHistory() }
        } catch {
            print("读取连接历史失败: \(error)")
        }
    }
    
    /// 持久化历史记录
    private func persistHistory() {
        do {
            let encoded = try JSONEncoder().encode(historyList)
            defaults.set(encoded, forKey: historyStorageKey)
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
                self.resetGoogleAccountState()
                // 正在运行的网页仍持有旧登录态，通知主界面断开它。
                self.webSessionResetToken += 1
                completion?()
            }
        }
    }

    /// 只退出本 App 内的 Google 账号（清除 Google 相关站点数据），保留其他网站缓存与连接记录。
    public func signOutGoogleAccounts(completion: (() -> Void)? = nil) {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let googleRecords = records.filter { record in
                let name = record.displayName.lowercased()
                return name.contains("google") || name.contains("gstatic") || name.contains("youtube")
            }
            dataStore.removeData(ofTypes: dataTypes, for: googleRecords) {
                DispatchQueue.main.async {
                    self.resetGoogleAccountState()
                    completion?()
                }
            }
        }
    }

    /// 登录 Cookie 清除后，所有会话编号与邮箱都不再可信。
    private func resetGoogleAccountState() {
        lastGoogleSessionIndex = nil
        for index in historyList.indices {
            historyList[index].googleSessionIndex = nil
            historyList[index].accountName = nil
        }
        persistHistory()
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
