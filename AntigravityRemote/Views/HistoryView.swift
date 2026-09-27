//
//  HistoryView.swift
//  AntigravityRemote
//
//  历史连接记录管理列表
//

import SwiftUI

/// 历史连接列表视图
public struct HistoryView: View {
    @ObservedObject public var settings: AppSettings
    public var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingClearAlert = false
    
    public init(settings: AppSettings, onSelect: @escaping (String) -> Void) {
        self.settings = settings
        self.onSelect = onSelect
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if settings.historyList.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 54))
                            .foregroundColor(.secondary.opacity(0.6))
                        
                        Text("暂无连接历史")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("连接过 Antigravity 远程控制后，地址会自动保存在这里方便随时一键重连。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(settings.historyList) { record in
                            Button {
                                HapticManager.medium()
                                dismiss()
                                onSelect(record.urlString)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                        .frame(width: 32, height: 32)
                                        .background(Color.blue.opacity(0.12))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(record.displayName)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            
                                            // 状态圆点与标签
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(record.status.color)
                                                    .frame(width: 6, height: 6)
                                                Text(record.status.rawValue)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(record.status.color)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(record.status.color.opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                        
                                        Text("上次使用: \(formattedDate(record.lastUsedAt))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            settings.removeConnection(at: indexSet)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("连接历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                if !settings.historyList.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("清空") {
                            showingClearAlert = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("清空所有历史", isPresented: $showingClearAlert) {
                Button("取消", role: .cancel) { }
                Button("清空全部", role: .destructive) {
                    HapticManager.heavy()
                    settings.clearAllHistory()
                }
            } message: {
                Text("确定要清空全部远程连接记录吗？")
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
