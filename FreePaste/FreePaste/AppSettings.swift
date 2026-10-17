//
//  AppSettings.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import Combine
import Carbon.HIToolbox
import Foundation

/// Stores user-facing preferences in UserDefaults so runtime behavior survives relaunches.
final class AppSettings: ObservableObject {
    enum RecordingPauseState: Codable, Equatable {
        case active
        case pausedManually
        case pausedUntil(Date)
    }

    enum Keys {
        static let maxItems = "settings.maxItems"
        static let visibleHistoryItemCount = "settings.visibleHistoryItemCount"
        static let autoPreviewEnabled = "settings.autoPreviewEnabled"
        static let maxTotalSizeMB = "settings.maxTotalSizeMB"
        static let retentionDays = "settings.retentionDays"
        static let deduplicateEnabled = "settings.deduplicateEnabled"
        static let blockedBundleIDs = "settings.blockedBundleIDs"
        static let recordingPauseState = "settings.recordingPauseState"
        static let nextItemShortcut = "settings.shortcuts.nextItem"
        static let previousItemShortcut = "settings.shortcuts.previousItem"
        static let deleteSelectedItemShortcut = "settings.shortcuts.deleteSelectedItem"
        static let focusSearchShortcut = "settings.shortcuts.focusSearch"
        static let globalToggleShortcut = "settings.shortcuts.globalToggle"
        static let batchPasteStartShortcut = "settings.shortcuts.batchPasteStart"
        static let batchPasteDirection = "settings.batchPasteDirection"
        static let switchPanelShortcut = "settings.shortcuts.switchPanel"
        static let togglePinShortcut = "settings.shortcuts.togglePin"
        static let plainTextPasteShortcut = "settings.shortcuts.plainTextPaste"
        static let navigationControlFBMigration = "settings.migrations.navigationControlFB"
        static let plainTextPasteShiftReturnMigration = "settings.migrations.plainTextPasteShiftReturn"
        static let searchCommandFMigration = "settings.migrations.searchCommandF"
        static let deleteCommandBackspaceMigration = "settings.migrations.deleteCommandBackspace"
    }

    @Published var maxItems: Int {
        didSet {
            let normalized = max(0, maxItems)
            if normalized != maxItems {
                maxItems = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.maxItems)
        }
    }

    @Published var visibleHistoryItemCount: Int {
        didSet {
            let normalized = min(20, max(3, visibleHistoryItemCount))
            if normalized != visibleHistoryItemCount {
                visibleHistoryItemCount = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.visibleHistoryItemCount)
        }
    }

    @Published var autoPreviewEnabled: Bool {
        didSet {
            defaults.set(autoPreviewEnabled, forKey: Keys.autoPreviewEnabled)
        }
    }

    @Published var maxTotalSizeMB: Int {
        didSet {
            let normalized = max(0, maxTotalSizeMB)
            if normalized != maxTotalSizeMB {
                maxTotalSizeMB = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.maxTotalSizeMB)
        }
    }

    @Published var retentionDays: Int {
        didSet {
            let normalized = max(0, retentionDays)
            if normalized != retentionDays {
                retentionDays = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.retentionDays)
        }
    }

    @Published var deduplicateEnabled: Bool {
        didSet {
            defaults.set(deduplicateEnabled, forKey: Keys.deduplicateEnabled)
        }
    }

    @Published var blockedBundleIDs: [String] {
        didSet {
            defaults.set(blockedBundleIDs, forKey: Keys.blockedBundleIDs)
        }
    }

    @Published var recordingPauseState: RecordingPauseState {
        didSet {
            saveRecordingPauseState(recordingPauseState)
            scheduleRecordingPauseExpiryTimer()
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard !isSynchronizingLaunchAtLogin, launchAtLoginEnabled != oldValue else { return }
            do {
                try launchAtLoginController.setEnabled(launchAtLoginEnabled)
                launchAtLoginErrorMessage = nil
            } catch {
                isSynchronizingLaunchAtLogin = true
                launchAtLoginEnabled = oldValue
                isSynchronizingLaunchAtLogin = false
                launchAtLoginErrorMessage = "无法更新开机自启，请稍后重试。"
            }
        }
    }

    @Published private(set) var launchAtLoginErrorMessage: String?
    @Published var nextItemShortcut: KeyboardShortcut {
        didSet { saveShortcut(nextItemShortcut, forKey: Keys.nextItemShortcut) }
    }
    @Published var previousItemShortcut: KeyboardShortcut {
        didSet { saveShortcut(previousItemShortcut, forKey: Keys.previousItemShortcut) }
    }
    @Published var deleteSelectedItemShortcut: KeyboardShortcut {
        didSet { saveShortcut(deleteSelectedItemShortcut, forKey: Keys.deleteSelectedItemShortcut) }
    }
    @Published var focusSearchShortcut: KeyboardShortcut {
        didSet { saveShortcut(focusSearchShortcut, forKey: Keys.focusSearchShortcut) }
    }
    @Published var globalToggleShortcut: KeyboardShortcut {
        didSet { saveShortcut(globalToggleShortcut, forKey: Keys.globalToggleShortcut) }
    }
    @Published var batchPasteStartShortcut: KeyboardShortcut {
        didSet { saveShortcut(batchPasteStartShortcut, forKey: Keys.batchPasteStartShortcut) }
    }
    @Published var batchPasteDirection: BatchPasteDirection {
        didSet { defaults.set(batchPasteDirection.rawValue, forKey: Keys.batchPasteDirection) }
    }
    @Published var switchPanelShortcut: KeyboardShortcut {
        didSet { saveShortcut(switchPanelShortcut, forKey: Keys.switchPanelShortcut) }
    }
    @Published var togglePinShortcut: KeyboardShortcut {
        didSet { saveShortcut(togglePinShortcut, forKey: Keys.togglePinShortcut) }
    }
    @Published var plainTextPasteShortcut: KeyboardShortcut {
        didSet { saveShortcut(plainTextPasteShortcut, forKey: Keys.plainTextPasteShortcut) }
    }

    private let defaults: UserDefaults
    private let launchAtLoginController: any LaunchAtLoginControlling
    private var isSynchronizingLaunchAtLogin = false
    private var recordingPauseExpiryTimer: Timer?

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginController: any LaunchAtLoginControlling = SystemLaunchAtLoginController()
    ) {
        self.defaults = defaults
        self.launchAtLoginController = launchAtLoginController
        if defaults.object(forKey: Keys.maxItems) == nil {
            self.maxItems = 0
        } else {
            self.maxItems = max(0, defaults.integer(forKey: Keys.maxItems))
        }

        if defaults.object(forKey: Keys.visibleHistoryItemCount) == nil {
            self.visibleHistoryItemCount = 5
        } else {
            self.visibleHistoryItemCount = min(20, max(3, defaults.integer(forKey: Keys.visibleHistoryItemCount)))
        }

        if defaults.object(forKey: Keys.autoPreviewEnabled) == nil {
            self.autoPreviewEnabled = true
        } else {
            self.autoPreviewEnabled = defaults.bool(forKey: Keys.autoPreviewEnabled)
        }

        if defaults.object(forKey: Keys.maxTotalSizeMB) == nil {
            self.maxTotalSizeMB = 0
        } else {
            self.maxTotalSizeMB = max(0, defaults.integer(forKey: Keys.maxTotalSizeMB))
        }

        if defaults.object(forKey: Keys.retentionDays) == nil {
            self.retentionDays = 0
        } else {
            self.retentionDays = max(0, defaults.integer(forKey: Keys.retentionDays))
        }

        if defaults.object(forKey: Keys.deduplicateEnabled) == nil {
            self.deduplicateEnabled = true
        } else {
            self.deduplicateEnabled = defaults.bool(forKey: Keys.deduplicateEnabled)
        }

        self.blockedBundleIDs = defaults.stringArray(forKey: Keys.blockedBundleIDs) ?? []
        let initialRecordingPauseState = Self.normalizedRecordingPauseState(
            Self.loadRecordingPauseState(from: defaults)
        )
        self.recordingPauseState = initialRecordingPauseState

        self.launchAtLoginEnabled = launchAtLoginController.isEnabled
        self.launchAtLoginErrorMessage = nil
        let navigationShortcuts = Self.loadNavigationShortcuts(from: defaults)
        self.nextItemShortcut = navigationShortcuts.next
        self.previousItemShortcut = navigationShortcuts.previous
        self.deleteSelectedItemShortcut = Self.loadDeleteShortcut(from: defaults)
        self.focusSearchShortcut = Self.loadSearchShortcut(from: defaults)
        self.globalToggleShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.globalToggleShortcut,
            fallback: .defaultGlobalToggle
        )
        self.batchPasteStartShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.batchPasteStartShortcut,
            fallback: .defaultBatchPasteStart
        )
        self.batchPasteDirection = defaults.string(forKey: Keys.batchPasteDirection)
            .flatMap(BatchPasteDirection.init(rawValue:)) ?? .forward
        self.switchPanelShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.switchPanelShortcut,
            fallback: .defaultSwitchPanel
        )
        self.togglePinShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.togglePinShortcut,
            fallback: .defaultTogglePin
        )
        self.plainTextPasteShortcut = Self.loadPlainTextPasteShortcut(from: defaults)
        scheduleRecordingPauseExpiryTimer()
    }

    func clearLaunchAtLoginError() {
        launchAtLoginErrorMessage = nil
    }

    func addBlockedApp(bundleID: String) {
        guard !blockedBundleIDs.contains(bundleID) else { return }
        blockedBundleIDs.append(bundleID)
    }

    func removeBlockedApp(bundleID: String) {
        blockedBundleIDs.removeAll { $0 == bundleID }
    }

    var effectiveRecordingPauseState: RecordingPauseState {
        let normalized = Self.normalizedRecordingPauseState(recordingPauseState)
        if normalized != recordingPauseState {
            recordingPauseState = normalized
        }
        return normalized
    }

    var isRecordingPaused: Bool {
        effectiveRecordingPauseState != .active
    }

    var isRecordingPausedManually: Bool {
        effectiveRecordingPauseState == .pausedManually
    }

    func pauseRecordingManually() {
        recordingPauseState = .pausedManually
    }

    func pauseRecording(for interval: TimeInterval) {
        guard interval > 0 else {
            resumeRecording()
            return
        }
        pauseRecording(until: Date().addingTimeInterval(interval))
    }

    func pauseRecording(until date: Date) {
        recordingPauseState = Self.normalizedRecordingPauseState(.pausedUntil(date))
    }

    func resumeRecording() {
        recordingPauseState = .active
    }

    func setManualRecordingPauseEnabled(_ enabled: Bool) {
        if enabled {
            pauseRecordingManually()
        } else {
            resumeRecording()
        }
    }

    var recordingPauseStatusText: String? {
        switch effectiveRecordingPauseState {
        case .active:
            return nil
        case .pausedManually:
            return "已手动暂停记录新内容。"
        case .pausedUntil(let deadline):
            return "已暂停记录新内容，将于 \(Self.pauseResumeTimeFormatter.string(from: deadline)) 自动恢复。"
        }
    }

    /// Returns the display name of the action that uses `shortcut`, excluding the action named `excludingName`.
    /// Returns nil if no conflict exists.
    func conflictingActionName(for shortcut: KeyboardShortcut, excludingName: String) -> String? {
        if shortcut == .defaultFocusSearch, excludingName != "聚焦搜索栏" {
            return "聚焦搜索栏"
        }
        if shortcut == .defaultSwitchPanel, excludingName != "切换最近/收藏" {
            return "切换最近/收藏"
        }
        if shortcut == KeyboardShortcut(keyCode: UInt16(kVK_Delete)) {
            return "搜索文本退格"
        }
        let all: [(String, KeyboardShortcut)] = [
            ("唤起/隐藏面板", globalToggleShortcut),
            ("启动批量收集", batchPasteStartShortcut),
            ("切换最近/收藏", switchPanelShortcut),
            ("下一项", nextItemShortcut),
            ("上一项", previousItemShortcut),
            ("删除选中项", deleteSelectedItemShortcut),
            ("聚焦搜索栏", focusSearchShortcut),
            ("收藏/取消收藏", togglePinShortcut),
            ("粘贴为纯文本", plainTextPasteShortcut),
        ]
        let reservedBatchPasteShortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_V),
            modifierFlags: .command
        )
        if shortcut == reservedBatchPasteShortcut {
            return "批量模式粘贴"
        }
        return all.first { $0.0 != excludingName && $0.1 == shortcut }?.0
    }

    func restoreDefaultShortcuts() {
        nextItemShortcut = .defaultNextItem
        previousItemShortcut = .defaultPreviousItem
        deleteSelectedItemShortcut = .defaultDeleteSelectedItem
        focusSearchShortcut = .defaultFocusSearch
        globalToggleShortcut = .defaultGlobalToggle
        batchPasteStartShortcut = .defaultBatchPasteStart
        switchPanelShortcut = .defaultSwitchPanel
        togglePinShortcut = .defaultTogglePin
        plainTextPasteShortcut = .defaultPlainTextPaste
    }

    private func saveShortcut(_ shortcut: KeyboardShortcut, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }

    private func saveRecordingPauseState(_ state: RecordingPauseState) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Keys.recordingPauseState)
    }

    private func scheduleRecordingPauseExpiryTimer() {
        recordingPauseExpiryTimer?.invalidate()
        recordingPauseExpiryTimer = nil

        guard case .pausedUntil(let deadline) = Self.normalizedRecordingPauseState(recordingPauseState) else {
            return
        }

        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else {
            recordingPauseState = .active
            return
        }

        recordingPauseExpiryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.resumeRecording()
        }
    }

    private static func loadRecordingPauseState(from defaults: UserDefaults) -> RecordingPauseState {
        guard
            let data = defaults.data(forKey: Keys.recordingPauseState),
            let state = try? JSONDecoder().decode(RecordingPauseState.self, from: data)
        else {
            return .active
        }
        return state
    }

    private static func normalizedRecordingPauseState(
        _ state: RecordingPauseState,
        now: Date = Date()
    ) -> RecordingPauseState {
        switch state {
        case .active, .pausedManually:
            return state
        case .pausedUntil(let deadline):
            return deadline > now ? state : .active
        }
    }

    private static let pauseResumeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func loadShortcut(
        from defaults: UserDefaults,
        key: String,
        fallback: KeyboardShortcut
    ) -> KeyboardShortcut {
        guard
            let data = defaults.data(forKey: key),
            let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else {
            return fallback
        }
        return shortcut
    }

    private static func loadPlainTextPasteShortcut(from defaults: UserDefaults) -> KeyboardShortcut {
        let shortcut = loadShortcut(
            from: defaults,
            key: Keys.plainTextPasteShortcut,
            fallback: .defaultPlainTextPaste
        )
        guard !defaults.bool(forKey: Keys.plainTextPasteShiftReturnMigration) else {
            return shortcut
        }

        defaults.set(true, forKey: Keys.plainTextPasteShiftReturnMigration)
        let legacyDefault = KeyboardShortcut(
            keyCode: UInt16(kVK_Return),
            modifierFlags: .option
        )
        guard shortcut == legacyDefault else { return shortcut }

        defaults.set(
            try? JSONEncoder().encode(KeyboardShortcut.defaultPlainTextPaste),
            forKey: Keys.plainTextPasteShortcut
        )
        return .defaultPlainTextPaste
    }

    private static func loadSearchShortcut(from defaults: UserDefaults) -> KeyboardShortcut {
        let shortcut = loadShortcut(
            from: defaults, key: Keys.focusSearchShortcut, fallback: .defaultFocusSearch
        )
        guard !defaults.bool(forKey: Keys.searchCommandFMigration) else { return shortcut }
        defaults.set(true, forKey: Keys.searchCommandFMigration)
        guard shortcut == KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Slash)) else { return shortcut }
        defaults.set(
            try? JSONEncoder().encode(KeyboardShortcut.defaultFocusSearch),
            forKey: Keys.focusSearchShortcut
        )
        return .defaultFocusSearch
    }

    private static func loadDeleteShortcut(from defaults: UserDefaults) -> KeyboardShortcut {
        let shortcut = loadShortcut(
            from: defaults, key: Keys.deleteSelectedItemShortcut, fallback: .defaultDeleteSelectedItem
        )
        guard !defaults.bool(forKey: Keys.deleteCommandBackspaceMigration) else { return shortcut }
        defaults.set(true, forKey: Keys.deleteCommandBackspaceMigration)
        guard shortcut == KeyboardShortcut(keyCode: UInt16(kVK_Delete)) else { return shortcut }
        defaults.set(
            try? JSONEncoder().encode(KeyboardShortcut.defaultDeleteSelectedItem),
            forKey: Keys.deleteSelectedItemShortcut
        )
        return .defaultDeleteSelectedItem
    }

    private static func loadNavigationShortcuts(
        from defaults: UserDefaults
    ) -> (next: KeyboardShortcut, previous: KeyboardShortcut) {
        let next = loadShortcut(
            from: defaults,
            key: Keys.nextItemShortcut,
            fallback: .defaultNextItem
        )
        let previous = loadShortcut(
            from: defaults,
            key: Keys.previousItemShortcut,
            fallback: .defaultPreviousItem
        )
        guard !defaults.bool(forKey: Keys.navigationControlFBMigration) else {
            return (next, previous)
        }

        defaults.set(true, forKey: Keys.navigationControlFBMigration)
        let legacyNext = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_N),
            modifierFlags: .control
        )
        let legacyPrevious = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_P),
            modifierFlags: .control
        )
        let migratedNext = next == legacyNext ? KeyboardShortcut.defaultNextItem : next
        let migratedPrevious = previous == legacyPrevious ? KeyboardShortcut.defaultPreviousItem : previous

        if migratedNext != next {
            defaults.set(
                try? JSONEncoder().encode(migratedNext),
                forKey: Keys.nextItemShortcut
            )
        }
        if migratedPrevious != previous {
            defaults.set(
                try? JSONEncoder().encode(migratedPrevious),
                forKey: Keys.previousItemShortcut
            )
        }
        return (migratedNext, migratedPrevious)
    }
}
