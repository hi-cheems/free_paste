//
//  SettingsView.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showAppPicker = false

    var body: some View {
        Form {
            Section("历史记录") {
                Stepper(value: $settings.maxItems, in: 0...500) {
                    HStack {
                        Text("最大条数")
                        Spacer()
                        Text(settings.maxItems == 0 ? "不限制" : "\(settings.maxItems)")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Text("设置为 0 表示不限制历史条目数量。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Stepper(value: $settings.maxTotalSizeMB, in: 0...1024) {
                    HStack {
                        Text("最大历史容量")
                        Spacer()
                        Text(settings.maxTotalSizeMB == 0 ? "不限制" : "\(settings.maxTotalSizeMB) MB")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Text("按文本、富文本、图片和文件路径的实际存储量计算；超出时会优先淘汰最旧记录。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Stepper(value: $settings.retentionDays, in: 0...365) {
                    HStack {
                        Text("记录保留时间")
                        Spacer()
                        Text(settings.retentionDays == 0 ? "永不过期" : "\(settings.retentionDays) 天")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Text("超过保留时间的记录会在启动时和新增历史时自动清理。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Toggle("连续相同内容去重", isOn: $settings.deduplicateEnabled)

                Text("开启后，复制已有内容时会将其提升到最前，不产生重复记录。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Section("启动") {
                Toggle("开机自动启动 FreePaste", isOn: $settings.launchAtLoginEnabled)

                Text("开启后，登录 macOS 时会自动启动 FreePaste。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                if let errorMessage = settings.launchAtLoginErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                }
            }

            Section("隐私") {
                Toggle(
                    "手动暂停记录新内容",
                    isOn: Binding(
                        get: { settings.isRecordingPausedManually },
                        set: { settings.setManualRecordingPauseEnabled($0) }
                    )
                )

                Text("开启后，新复制的内容不会进入历史；已有记录仍可查看、搜索和使用。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                HStack {
                    Button("暂停 5 分钟") {
                        settings.pauseRecording(for: 5 * 60)
                    }
                    Button("暂停 15 分钟") {
                        settings.pauseRecording(for: 15 * 60)
                    }
                    Button("恢复记录新内容") {
                        settings.resumeRecording()
                    }
                    .disabled(!settings.isRecordingPaused)
                }

                if let pauseStatusText = settings.recordingPauseStatusText {
                    Text(pauseStatusText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }

                if settings.blockedBundleIDs.isEmpty {
                    Text("未设置黑名单应用")
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(settings.blockedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            if let icon = appIcon(for: bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }
                            Text(appDisplayName(for: bundleID))
                            Spacer()
                            Button {
                                settings.removeBlockedApp(bundleID: bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(AppTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("添加应用…") { showAppPicker = true }
                Text("已加入黑名单的应用，其复制操作不会被记录到历史。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .sheet(isPresented: $showAppPicker) {
                AppPickerSheet(blockedBundleIDs: settings.blockedBundleIDs) { bundleID in
                    settings.addBlockedApp(bundleID: bundleID)
                }
            }

            Section("全局快捷键") {
                ShortcutRecorderRow(
                    title: "唤起/隐藏面板",
                    shortcut: settings.globalToggleShortcut,
                    defaultLabel: KeyboardShortcut.defaultGlobalToggle.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "唤起/隐藏面板") }
                ) { settings.globalToggleShortcut = $0 }

                ShortcutRecorderRow(
                    title: "启动批量收集",
                    shortcut: settings.batchPasteStartShortcut,
                    defaultLabel: KeyboardShortcut.defaultBatchPasteStart.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "启动批量收集") }
                ) { settings.batchPasteStartShortcut = $0 }

                Text("全局快捷键需要包含 ⌘ 或 ⌃ 修饰键，修改后立即生效。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Section("面板内快捷键") {
                ShortcutRecorderRow(
                    title: "切换最近/收藏",
                    shortcut: settings.switchPanelShortcut,
                    defaultLabel: KeyboardShortcut.defaultSwitchPanel.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "切换最近/收藏") }
                ) { settings.switchPanelShortcut = $0 }

                ShortcutRecorderRow(
                    title: "下一项",
                    shortcut: settings.nextItemShortcut,
                    defaultLabel: KeyboardShortcut.defaultNextItem.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "下一项") }
                ) { settings.nextItemShortcut = $0 }

                ShortcutRecorderRow(
                    title: "上一项",
                    shortcut: settings.previousItemShortcut,
                    defaultLabel: KeyboardShortcut.defaultPreviousItem.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "上一项") }
                ) { settings.previousItemShortcut = $0 }

                ShortcutRecorderRow(
                    title: "删除选中项",
                    shortcut: settings.deleteSelectedItemShortcut,
                    defaultLabel: KeyboardShortcut.defaultDeleteSelectedItem.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "删除选中项") }
                ) { settings.deleteSelectedItemShortcut = $0 }

                ShortcutRecorderRow(
                    title: "聚焦搜索栏",
                    shortcut: settings.focusSearchShortcut,
                    defaultLabel: KeyboardShortcut.defaultFocusSearch.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "聚焦搜索栏") }
                ) { settings.focusSearchShortcut = $0 }

                ShortcutRecorderRow(
                    title: "收藏/取消收藏",
                    shortcut: settings.togglePinShortcut,
                    defaultLabel: KeyboardShortcut.defaultTogglePin.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "收藏/取消收藏") }
                ) { settings.togglePinShortcut = $0 }

                ShortcutRecorderRow(
                    title: "粘贴为纯文本",
                    shortcut: settings.plainTextPasteShortcut,
                    defaultLabel: KeyboardShortcut.defaultPlainTextPaste.displayText,
                    conflictChecker: { settings.conflictingActionName(for: $0, excludingName: "粘贴为纯文本") }
                ) { settings.plainTextPasteShortcut = $0 }

                Button("恢复默认快捷键") {
                    settings.restoreDefaultShortcuts()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .background(
            LinearGradient(
                colors: [AppTheme.panelTop, AppTheme.panelBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .tint(AppTheme.accent)
        .preferredColorScheme(.light)
    }

    private func appDisplayName(for bundleID: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return app.localizedName ?? bundleID
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? bundleID
        }
        return bundleID
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct AppPickerSheet: View {
    let blockedBundleIDs: [String]
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择要屏蔽的应用")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding()

            Divider()

            if runningApps.isEmpty {
                Spacer()
                Text("没有可添加的应用")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(runningApps, id: \.processIdentifier) { app in
                    Button {
                        if let id = app.bundleIdentifier { onAdd(id) }
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }
                            Text(app.localizedName ?? app.bundleIdentifier ?? "未知")
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 300, height: 360)
        .preferredColorScheme(.light)
        .onAppear {
            runningApps = NSWorkspace.shared.runningApplications
                .filter { app in
                    app.activationPolicy == .regular
                        && app.bundleIdentifier != Bundle.main.bundleIdentifier
                        && !blockedBundleIDs.contains(app.bundleIdentifier ?? "")
                }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
