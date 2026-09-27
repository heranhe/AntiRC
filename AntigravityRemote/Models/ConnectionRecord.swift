//
//  ConnectionRecord.swift
//  AntigravityRemote
//
//  连接记录与账户数据模型，记录连接状态、Google 账户信息与设备备注
//

import SwiftUI

/// 远程连接与账户在线状态
public enum ConnectionStatus: String, Codable, Equatable, Hashable {
    case connected = "已登录"
    case disconnected = "已断开"
    case connecting = "连接中"
    
    public var color: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .secondary.opacity(0.7)
        case .connecting:
            return .orange
        }
    }
}

/// 远程连接与账户记录模型
public struct ConnectionRecord: Identifiable, Codable, Equatable, Hashable {
    /// 唯一标识符
    public var id: UUID
    /// 自定义别名或备注名称（如“工位 Mac mini”）
    public var deviceAlias: String?
    /// 绑定的 Google 账户名或邮箱（如“user@gmail.com”）
    public var accountName: String?
    /// 连接状态（已登录、已断开、连接中）
    public var status: ConnectionStatus
    /// 远程控制 URL 字符串
    public var urlString: String
    /// 创建时间
    public var createdAt: Date
    /// 上次使用时间
    public var lastUsedAt: Date
    
    public init(
        id: UUID = UUID(),
        deviceAlias: String? = nil,
        accountName: String? = nil,
        status: ConnectionStatus = .disconnected,
        urlString: String,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.deviceAlias = deviceAlias
        self.accountName = accountName
        self.status = status
        self.urlString = urlString
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
    
    // MARK: - 兼容旧版 Codable 解码
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case deviceAlias
        case accountName
        case status
        case urlString
        case createdAt
        case lastUsedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.urlString = try container.decode(String.self, forKey: .urlString)
        self.deviceAlias = try container.decodeIfPresent(String.self, forKey: .deviceAlias)
        self.accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        self.status = try container.decodeIfPresent(ConnectionStatus.self, forKey: .status) ?? .disconnected
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()
        
        // 兼容旧版 title 字段
        if self.deviceAlias == nil, let oldTitle = try container.decodeIfPresent(String.self, forKey: .title), !oldTitle.isEmpty {
            if !oldTitle.contains("accounts.google.com") && !oldTitle.contains("http") {
                self.deviceAlias = oldTitle
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceAlias, forKey: .deviceAlias)
        try container.encode(accountName, forKey: .accountName)
        try container.encode(status, forKey: .status)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUsedAt, forKey: .lastUsedAt)
    }
    
    // MARK: - 友好名称计算属性
    
    /// 电脑/设备工作区主标题（物理载体：明确连接的是哪台电脑）
    public var deviceTitle: String {
        if let alias = deviceAlias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return alias
        }
        let lower = urlString.lowercased()
        if lower.contains("localhost") || lower.contains("127.0.0.1") {
            return "本地 Mac 智能体"
        }
        if lower.contains("accounts.google.com") {
            return "我的 Mac 电脑"
        }
        if let url = URL(string: urlString), let host = url.host {
            return "\(host) 设备"
        }
        return "Mac 远程工作区"
    }
    
    /// 去除多余前缀，直接提取账户名称
    public static func sanitizeAccountName(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Google Account:",
            "Google Account：",
            "Google account:",
            "Google 账号:",
            "Google 账号：",
            "Google 帳號:",
            "Google 帳號：",
            "Google 账户:",
            "Google 账户："
        ]
        for prefix in prefixes {
            if text.lowercased().hasPrefix(prefix.lowercased()) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    /// 绑定的账户或身份副标题（直接显示纯净账户名）
    public var accountSubtitle: String {
        if let account = accountName, !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sanitized = ConnectionRecord.sanitizeAccountName(account)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        if isGoogleAccount {
            return "已连接账户"
        }
        return "Antigravity 工作区"
    }
    
    /// 获取在界面上呈现的核心主标题
    public var displayName: String {
        deviceTitle
    }
    
    /// 是否属于 Google 账户关联的会话
    public var isGoogleAccount: Bool {
        urlString.lowercased().contains("google.com") ||
        (accountName != nil && !accountName!.isEmpty)
    }
    
    /// 智能友好名称生成
    public static func smartFriendlyName(for urlString: String) -> String {
        let lower = urlString.lowercased()
        if lower.contains("accounts.google.com") {
            return "我的 Mac 电脑"
        }
        guard let url = URL(string: urlString) else {
            return "Antigravity 远程实例"
        }
        if let host = url.host {
            if host == "localhost" || host == "127.0.0.1" {
                return "本地 Antigravity 智能体"
            }
            return "\(host) 远程实例"
        }
        return "Antigravity 远程工作区"
    }
}
