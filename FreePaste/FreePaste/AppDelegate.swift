//
//  AppDelegate.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/13.
//

import AppKit
import Combine
import SwiftUI
import Carbon

/// Abstracts the Settings jump so permission guidance can be tested without opening System Settings.
protocol SystemSettingsOpening {
    @discardableResult
    func openAccessibilitySettings() -> Bool
    @discardableResult
    func openInputMonitoringSettings() -> Bool
}

struct WorkspaceSystemSettingsOpener: SystemSettingsOpening {
    @discardableResult
    func openAccessibilitySettings() -> Bool {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    func openInputMonitoringSettings() -> Bool {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
        else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}

/// Owns the menu bar lifecycle and keeps application-level side effects out of SwiftUI views.
final class AppDelegate: NSObject, NSApplicationDelegate {
    enum GlobalHotKeyAction: Equatable {
        case none
        case toggleHistory
        case startBatchPaste
    }

    private enum BatchPastePermission {
        case accessibility
        case inputMonitoring
    }

    private enum GlobalHotKey {
        static let signature: OSType = 0x6670_7374 // "fpst"
        static let historyPanelID: UInt32 = 1
        static let batchPasteID: UInt32 = 2
    }

    static func globalHotKeyAction(
        hotKeyID: UInt32,
        eventKind: UInt32
    ) -> GlobalHotKeyAction {
        switch (hotKeyID, eventKind) {
        case (GlobalHotKey.historyPanelID, UInt32(kEventHotKeyPressed)):
            return .toggleHistory
        case (GlobalHotKey.batchPasteID, UInt32(kEventHotKeyReleased)):
            return .startBatchPaste
        default:
            return .none
        }
    }

    private var statusItem: NSStatusItem!
    private var historyPanel: HistoryPanel!
    private var batchPastePanelController: BatchPastePanelController?
    private var settingsWindowController: NSWindowController?
    let settings: AppSettings
    let manager: ClipboardManager
    private var hotKeyRef: EventHotKeyRef?
    private var batchPasteHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let frontmostApplicationProvider: any FrontmostApplicationProviding
    private let directPasteService: any DirectPasteServicing
    private let batchPasteSelectionCaptureService: any BatchPasteSelectionCapturing
    private let systemSettingsOpener: any SystemSettingsOpening
    private let uiState: AppUIState
    private(set) var restoreTargetApplication: (any RunningApplication)?
    private var lastDirectPasteResult: DirectPasteResult?
    let previewPresenter: any ItemPreviewPresenting
    let batchPasteSession: BatchPasteSession
    private var cancellables = Set<AnyCancellable>()
    private var workspaceActivationObserver: NSObjectProtocol?
    private var isPreparingBatchPaste = false
    private lazy var batchPasteKeyInterceptor = BatchPasteKeyInterceptor { [weak self] in
        self?.handleBatchPasteCommand()
    }

    override init() {
        let settings = AppSettings()
        self.settings = settings
        self.manager = ClipboardManager(
            monitor: ClipboardMonitor(),
            store: ClipboardHistoryStore(),
            settings: settings
        )
        frontmostApplicationProvider = WorkspaceFrontmostApplicationProvider()
        directPasteService = DirectPasteService()
        batchPasteSelectionCaptureService = BatchPasteSelectionCaptureService()
        systemSettingsOpener = WorkspaceSystemSettingsOpener()
        uiState = AppUIState()
        previewPresenter = ItemPreviewPresenter(settings: settings)
        batchPasteSession = BatchPasteSession(direction: settings.batchPasteDirection)
        super.init()
    }

    init(
        frontmostApplicationProvider: any FrontmostApplicationProviding,
        directPasteService: any DirectPasteServicing,
        systemSettingsOpener: any SystemSettingsOpening = WorkspaceSystemSettingsOpener(),
        uiState: AppUIState,
        settings: AppSettings = AppSettings(),
        previewPresenter: (any ItemPreviewPresenting)? = nil,
        batchPasteSelectionCaptureService: any BatchPasteSelectionCapturing = BatchPasteSelectionCaptureService()
    ) {
        self.settings = settings
        self.manager = ClipboardManager(
            monitor: ClipboardMonitor(),
            store: ClipboardHistoryStore(inMemory: true),
            settings: settings
        )
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.directPasteService = directPasteService
        self.batchPasteSelectionCaptureService = batchPasteSelectionCaptureService
        self.systemSettingsOpener = systemSettingsOpener
        self.uiState = uiState
        self.previewPresenter = previewPresenter ?? ItemPreviewPresenter(settings: settings)
        self.batchPasteSession = BatchPasteSession(direction: settings.batchPasteDirection)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHistoryPanel()
        setupBatchPastePanel()
        registerGlobalHotKeys()
        observeGlobalShortcutChanges()
        observeBatchPasteState()
        observeFrontmostApplicationChanges()
        manager.start()

        #if DEBUG
        if CommandLine.arguments.contains("--show-history-panel-for-testing") {
            DispatchQueue.main.async { [weak self] in
                self?.toggleHistoryPanel()
            }
        }
        if CommandLine.arguments.contains("--show-batch-panel-for-testing") {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let initialItem = self.manager.currentItemForBatchPaste()
                    ?? ClipboardItem(content: .text("批量面板测试"))
                guard self.batchPasteSession.start(
                    with: initialItem,
                    direction: self.settings.batchPasteDirection
                ) else { return }
                self.batchPastePanelController?.showWithoutActivating()
            }
        }
        if CommandLine.arguments.contains("--start-batch-paste-for-testing") {
            DispatchQueue.main.async { [weak self] in
                self?.startOrRevealBatchPasteMode()
            }
        }
        #endif
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = makeStatusItemImage(isBatchPasteActive: false)
        button.action = #selector(statusButtonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    private func makeStatusItemImage(isBatchPasteActive: Bool) -> NSImage? {
        guard let baseImage = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "FreePaste")
        else {
            return nil
        }
        baseImage.size = NSSize(width: 18, height: 18)
        guard isBatchPasteActive else {
            baseImage.isTemplate = true
            return baseImage
        }

        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            baseImage.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func updateStatusItemImage() {
        statusItem?.button?.image = makeStatusItemImage(
            isBatchPasteActive: batchPasteSession.isActive
        )
    }

    @objc private func statusButtonClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleHistoryPanel()
        }
    }

    private func showContextMenu() {
        let isRecordingPaused = settings.isRecordingPaused
        let menu = NSMenu()
        let shortcutItem = NSMenuItem(title: "全局快捷键：\(settings.globalToggleShortcut.displayText)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)
        if let pauseStatusText = settings.recordingPauseStatusText {
            let statusItem = NSMenuItem(title: pauseStatusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        let pauseMenuItem = NSMenuItem(title: "暂停记录新内容", action: nil, keyEquivalent: "")
        let pauseSubmenu = NSMenu()
        let pauseFiveMinutesItem = NSMenuItem(title: "暂停 5 分钟", action: #selector(pauseRecordingForFiveMinutes), keyEquivalent: "")
        pauseFiveMinutesItem.target = self
        pauseSubmenu.addItem(pauseFiveMinutesItem)
        let pauseFifteenMinutesItem = NSMenuItem(title: "暂停 15 分钟", action: #selector(pauseRecordingForFifteenMinutes), keyEquivalent: "")
        pauseFifteenMinutesItem.target = self
        pauseSubmenu.addItem(pauseFifteenMinutesItem)
        let pauseManualItem = NSMenuItem(title: "暂停直到手动恢复", action: #selector(pauseRecordingManually), keyEquivalent: "")
        pauseManualItem.target = self
        pauseSubmenu.addItem(pauseManualItem)
        pauseMenuItem.submenu = pauseSubmenu
        menu.addItem(pauseMenuItem)

        let resumeItem = NSMenuItem(title: "恢复记录新内容", action: nil, keyEquivalent: "")
        if isRecordingPaused {
            resumeItem.action = #selector(resumeRecording)
            resumeItem.target = self
            resumeItem.isEnabled = true
        } else {
            resumeItem.isEnabled = false
        }
        menu.addItem(resumeItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 FreePaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func pauseRecordingForFiveMinutes() {
        settings.pauseRecording(for: 5 * 60)
    }

    @objc private func pauseRecordingForFifteenMinutes() {
        settings.pauseRecording(for: 15 * 60)
    }

    @objc private func pauseRecordingManually() {
        settings.pauseRecordingManually()
    }

    @objc private func resumeRecording() {
        settings.resumeRecording()
    }

    @objc private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            let contentView = SettingsView()
                .environmentObject(settings)
            let hostingController = NSHostingController(rootView: contentView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 420, height: 300))
            window.center()
            applyFixedAppearance(to: window)
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        if let window = settingsWindowController?.window {
            applyFixedAppearance(to: window)
        }
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - History Panel

    private func setupHistoryPanel() {
        let hostingController = NSHostingController(
            rootView:
                ClipboardHistoryView(
                    onConfirm: { [weak self] item in
                        self?.handleConfirmedItem(item)
                    },
                    onOpenSettings: { [weak self] in
                        self?.hideHistoryPanel()
                        self?.openSettingsWindow()
                    },
                    onPreview: { [weak self] item in
                        self?.showPreviewOrToggle(item)
                    },
                    onClosePreview: { [weak self] in
                        self?.previewPresenter.closePreview()
                    },
                    onPlainTextConfirm: { [weak self] item in
                        self?.handleConfirmedItemAsPlainText(item)
                    },
                    onCancel: { [weak self] in
                        self?.handleCancelledPopover()
                    }
                )
                .environmentObject(manager)
                .environmentObject(settings)
                .environmentObject(uiState)
        )
        applyTransparentBackground(to: hostingController.view)
        let panel = HistoryPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 720,
                height: ClipboardHistoryPanelLayout.minimumHeight
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.hasShadow = false
        applyFixedAppearance(to: panel)
        historyPanel = panel
    }

    @objc func toggleHistoryPanel() {
        if batchPasteSession.isActive {
            batchPastePanelController?.bringToFront()
            return
        }
        if historyPanel.isVisible {
            previewPresenter.closePreview()
            hideHistoryPanel()
        } else {
            // Capture the app that was active before FreePaste steals focus so direct paste can restore it.
            uiState.clearInlineMessage()
            if case .missingAccessibilityPermission = lastDirectPasteResult,
               directPasteService.requestAccessibilityPermissionIfNeeded() {
                lastDirectPasteResult = nil
            }
            captureRestoreTargetApplication()
            NSApp.activate(ignoringOtherApps: true)
            positionHistoryPanel()
            historyPanel.makeKeyAndOrderFront(nil)
            uiState.markHistoryPopoverPresented()
        }
    }

    private func positionHistoryPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }
        historyPanel.setFrame(
            ClipboardHistoryPanelLayout.frame(in: screen.visibleFrame),
            display: true
        )
    }

    private func hideHistoryPanel() {
        if historyPanel?.isVisible == true {
            historyPanel.orderOut(nil)
        }
        if uiState.isHistoryPopoverVisible {
            uiState.markHistoryPopoverDismissed()
        }
    }

    private func handleConfirmedItem(_ item: ClipboardItem) {
        // Direct paste always starts from a known clipboard state, so copy first and automate after.
        manager.copyToPasteboard(item)
        handleDirectPasteFlow()
    }

    func handleConfirmedItemForTesting(_ item: ClipboardItem) {
        handleConfirmedItem(item)
    }

    private func handleConfirmedItemAsPlainText(_ item: ClipboardItem) {
        guard manager.copyToPasteboardAsPlainText(item) else { return }
        handleDirectPasteFlow()
    }

    func handleConfirmedItemAsPlainTextForTesting(_ item: ClipboardItem) {
        handleConfirmedItemAsPlainText(item)
    }

    func handleCancelledPopoverForTesting() {
        handleCancelledPopover()
    }

    private func handleCancelledPopover() {
        previewPresenter.closePreview()
        hideHistoryPanel()
        restoreFocusToCapturedApplication()
    }

    func captureRestoreTargetApplication() {
        restoreTargetApplication = resolvedRestoreTarget(
            from: frontmostApplicationProvider.frontmostApplication
        )
    }

    func resolvedRestoreTarget(
        from application: (any RunningApplication)?
    ) -> (any RunningApplication)? {
        guard let application, shouldTrackAsRestoreTarget(application) else {
            return nil
        }
        return application
    }

    func shouldTrackAsRestoreTarget(_ application: any RunningApplication) -> Bool {
        // Ignore FreePaste itself whether it is identified by pid or by bundle id.
        if application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           application.bundleIdentifier == bundleIdentifier {
            return false
        }

        return true
    }

    private func restoreFocusToCapturedApplication() {
        NSApp.deactivate()
        _ = restoreTargetApplication?.activate(options: [])
    }

    private func handleDirectPasteFlow() {
        guard directPasteService.requestAccessibilityPermissionIfNeeded() else {
            lastDirectPasteResult = .missingAccessibilityPermission
            uiState.showInlineMessage(
                "需要开启辅助功能权限后才能直接粘贴。授权后请重试。",
                actionTitle: "去授权"
            ) { [weak self] in
                self?.openAccessibilitySettings()
            }
            NSSound.beep()
            return
        }

        uiState.clearInlineMessage()
        previewPresenter.closePreview()
        hideHistoryPanel()
        // Step out of the way before trying to reactivate the previous app.
        NSApp.deactivate()

        let result = directPasteService.pasteBack(to: restoreTargetApplication)
        lastDirectPasteResult = result

        if result != .success {
            uiState.showWarningMessage(message(for: result))
            NSSound.beep()
        }
    }

    private func openAccessibilitySettings() {
        if !systemSettingsOpener.openAccessibilitySettings() {
            uiState.showWarningMessage("无法打开系统设置，请前往“系统设置 > 隐私与安全性 > 辅助功能”为 FreePaste 授权。")
            NSSound.beep()
        }
    }

    private func message(for result: DirectPasteResult) -> String {
        switch result {
        case .success:
            return ""
        case .noTargetApplication:
            return "没有可恢复的目标应用，已复制到剪贴板。"
        case .missingAccessibilityPermission:
            return "需要开启辅助功能权限后才能直接粘贴。授权后请重试。"
        case .activationFailed:
            return "无法切回原应用，已复制到剪贴板。"
        case .eventDispatchFailed:
            return "已切回原应用，但发送粘贴指令失败。"
        }
    }

    // MARK: - Batch Paste

    private func setupBatchPastePanel() {
        batchPastePanelController = BatchPastePanelController(
            session: batchPasteSession,
            onDirectionChange: { [weak self] direction in
                guard let self else { return }
                self.batchPasteSession.setDirection(direction)
                self.settings.batchPasteDirection = direction
            },
            onPaste: { [weak self] itemID in
                self?.handleBatchPasteCommand(preferredItemID: itemID)
            },
            onDelete: { [weak self] itemID in
                self?.batchPasteSession.remove(id: itemID)
            },
            onClose: { [weak self] in
                self?.finishBatchPasteMode()
            }
        )
    }

    private func observeBatchPasteState() {
        manager.capturedItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self, self.batchPasteSession.isActive else { return }
                self.batchPasteSession.add(item)
            }
            .store(in: &cancellables)

        batchPasteSession.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                self.statusItem?.button?.image = self.makeStatusItemImage(
                    isBatchPasteActive: isActive
                )
                if !isActive {
                    self.batchPasteKeyInterceptor.stop()
                    self.batchPastePanelController?.close()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func startOrRevealBatchPasteMode() {
        if batchPasteSession.isActive {
            batchPastePanelController?.bringToFront()
            return
        }
        guard !isPreparingBatchPaste else { return }
        guard directPasteService.requestAccessibilityPermissionIfNeeded() else {
            showBatchPastePermissionGuidance(for: .accessibility)
            return
        }
        guard CGPreflightListenEventAccess() else {
            showBatchPastePermissionGuidance(for: .inputMonitoring)
            return
        }

        captureLatestBatchPasteTarget()
        isPreparingBatchPaste = true
        batchPasteSelectionCaptureService.captureSelection { [weak self] didCaptureSelection in
            guard let self else { return }
            self.isPreparingBatchPaste = false
            guard didCaptureSelection else {
                self.showBatchPasteStartFailure(
                    title: "没有复制到选中内容",
                    message: "请先在当前应用中选中文本、图片或文件，然后再次启动批量收集。"
                )
                return
            }
            self.startBatchPasteWithCurrentClipboard()
        }
    }

    private func startBatchPasteWithCurrentClipboard() {
        guard !batchPasteSession.isActive else {
            batchPastePanelController?.bringToFront()
            return
        }
        guard let initialItem = manager.currentItemForBatchPaste() else {
            showBatchPasteStartFailure(
                title: "无法读取选中内容",
                message: "当前应用复制的内容暂不受支持。"
            )
            return
        }
        guard batchPasteKeyInterceptor.start() else {
            showBatchPastePermissionGuidance(for: .inputMonitoring)
            return
        }
        guard batchPasteSession.start(
            with: initialItem,
            direction: settings.batchPasteDirection
        ) else {
            batchPasteKeyInterceptor.stop()
            showBatchPasteStartFailure(
                title: "当前剪贴板内容过大",
                message: "单次批量收集最多可使用 256 MB 内存。"
            )
            return
        }

        previewPresenter.closePreview()
        hideHistoryPanel()
        batchPastePanelController?.showWithoutActivating()
    }

    private func finishBatchPasteMode() {
        batchPasteSession.finish()
        batchPasteKeyInterceptor.stop()
        batchPastePanelController?.close()
        updateStatusItemImage()
    }

    private func handleBatchPasteCommand(preferredItemID: ClipboardItem.ID? = nil) {
        guard batchPasteSession.isActive else { return }
        captureLatestBatchPasteTarget()
        if let preferredItemID {
            batchPasteSession.selectedItemID = preferredItemID
        }

        guard let item = batchPasteSession.takeNext() else {
            let target = restoreTargetApplication
            finishBatchPasteMode()
            NSApp.deactivate()
            _ = directPasteService.pasteBack(to: target)
            return
        }

        manager.copyToPasteboard(item)
        NSApp.deactivate()
        lastDirectPasteResult = directPasteService.pasteBack(to: restoreTargetApplication)
    }

    func handleBatchPasteCommandForTesting(preferredItemID: ClipboardItem.ID? = nil) {
        handleBatchPasteCommand(preferredItemID: preferredItemID)
    }

    private func captureLatestBatchPasteTarget() {
        guard let target = resolvedRestoreTarget(
            from: frontmostApplicationProvider.frontmostApplication
        ) else {
            return
        }
        restoreTargetApplication = target
    }

    private func observeFrontmostApplicationChanges() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                self.batchPasteSession.isActive,
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                self.shouldTrackAsRestoreTarget(application)
            else {
                return
            }
            self.restoreTargetApplication = application
        }
    }

    private func showBatchPastePermissionGuidance(for permission: BatchPastePermission) {
        let alert = NSAlert()
        switch permission {
        case .accessibility:
            alert.messageText = "批量粘贴需要辅助功能权限"
            alert.informativeText = "FreePaste 需要将内容粘贴回当前应用。授权后请再次启动批量收集。"
        case .inputMonitoring:
            alert.messageText = "批量粘贴需要输入监控权限"
            alert.informativeText = "FreePaste 需要在批量模式期间接管 Command+V。授权后请再次启动批量收集。"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            switch permission {
            case .accessibility:
                openAccessibilitySettings()
            case .inputMonitoring:
                openInputMonitoringSettings()
            }
        }
    }

    private func showBatchPasteStartFailure(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func openInputMonitoringSettings() {
        if !systemSettingsOpener.openInputMonitoringSettings() {
            uiState.showWarningMessage("无法打开系统设置，请前往“系统设置 > 隐私与安全性 > 输入监控”为 FreePaste 授权。")
            NSSound.beep()
        }
    }

    // MARK: - Global Hot Key (Carbon, no Accessibility permission needed)

    private func registerGlobalHotKeys() {
        // Install the event handler only once; re-registrations only swap the hotkey.
        if eventHandlerRef == nil {
            let eventSpecs = [
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard),
                    eventKind: UInt32(kEventHotKeyPressed)
                ),
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard),
                    eventKind: UInt32(kEventHotKeyReleased)
                )
            ]
            _ = eventSpecs.withUnsafeBufferPointer { buffer in
                InstallEventHandler(
                    GetApplicationEventTarget(),
                    { _, event, userData -> OSStatus in
                        guard let event, let ptr = userData else { return OSStatus(noErr) }
                        let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                        var hotKeyID = EventHotKeyID()
                        let status = GetEventParameter(
                            event,
                            EventParamName(kEventParamDirectObject),
                            EventParamType(typeEventHotKeyID),
                            nil,
                            MemoryLayout<EventHotKeyID>.size,
                            nil,
                            &hotKeyID
                        )
                        guard status == noErr else { return status }
                        let action = AppDelegate.globalHotKeyAction(
                            hotKeyID: hotKeyID.id,
                            eventKind: GetEventKind(event)
                        )
                        MainActor.assumeIsolated {
                            switch action {
                            case .none:
                                break
                            case .toggleHistory:
                                delegate.toggleHistoryPanel()
                            case .startBatchPaste:
                                DispatchQueue.main.async { [weak delegate] in
                                    delegate?.startOrRevealBatchPasteMode()
                                }
                            }
                        }
                        return OSStatus(noErr)
                    },
                    buffer.count, buffer.baseAddress,
                    Unmanaged.passUnretained(self).toOpaque(),
                    &eventHandlerRef
                )
            }
        }

        // Unregister the previous hotkey if any.
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = batchPasteHotKeyRef {
            UnregisterEventHotKey(ref)
            batchPasteHotKeyRef = nil
        }

        let historyShortcut = settings.globalToggleShortcut
        let historyHotKeyID = EventHotKeyID(
            signature: GlobalHotKey.signature,
            id: GlobalHotKey.historyPanelID
        )
        RegisterEventHotKey(
            UInt32(historyShortcut.keyCode),
            historyShortcut.carbonModifiers,
            historyHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        let batchShortcut = settings.batchPasteStartShortcut
        let batchHotKeyID = EventHotKeyID(
            signature: GlobalHotKey.signature,
            id: GlobalHotKey.batchPasteID
        )
        RegisterEventHotKey(
            UInt32(batchShortcut.keyCode),
            batchShortcut.carbonModifiers,
            batchHotKeyID,
            GetApplicationEventTarget(),
            0,
            &batchPasteHotKeyRef
        )
    }

    private func observeGlobalShortcutChanges() {
        Publishers.CombineLatest(
            settings.$globalToggleShortcut,
            settings.$batchPasteStartShortcut
        )
            .dropFirst()
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerGlobalHotKeys()
            }
            .store(in: &cancellables)
    }

    // MARK: - Item Preview Panel

    func showPreview(_ item: ClipboardItem) {
        previewPresenter.showPreview(for: item, nearWindow: historyPanel)
    }

    func showPreviewOrToggle(_ item: ClipboardItem) {
        if previewPresenter.isShowingPreview {
            if previewPresenter.previewItemID == item.id {
                previewPresenter.closePreview()
                return
            }
            previewPresenter.closePreview()
        }
        previewPresenter.showPreview(for: item, nearWindow: historyPanel)
    }

    // MARK: - Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = batchPasteHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        batchPasteKeyInterceptor.stop()
        batchPasteSession.finish()
        manager.stop()
    }

    func applicationDidResignActive(_ notification: Notification) {
        previewPresenter.closePreview()
        hideHistoryPanel()
    }
}

private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension AppDelegate {
    func applyFixedAppearance(to window: NSWindow) {
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        if let contentView = window.contentView {
            applyTransparentBackground(to: contentView)
        }
    }

    func applyTransparentBackground(to view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
