//
//  AppDelegateAndDirectPasteServiceTests.swift
//  FreePasteTests
//
//  Created by Codex on 2026/3/15.
//

import AppKit
import Carbon.HIToolbox
import XCTest

@testable import FreePaste

final class AppDelegateAndDirectPasteServiceTests: XCTestCase {

    func test_captureRestoreTargetApplication_usesFrontmostNonSelfApp() async {
        await MainActor.run {
            let frontmostApp = MockRunningApplication(
                bundleIdentifier: "com.example.notes",
                processIdentifier: 999
            )
            let uiState = AppUIState()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(
                    frontmostApplication: frontmostApp
                ),
                directPasteService: MockDirectPasteService(),
                uiState: uiState
            )

            delegate.captureRestoreTargetApplication()

            XCTAssertEqual(delegate.restoreTargetApplication?.processIdentifier, frontmostApp.processIdentifier)
        }
    }

    func test_captureRestoreTargetApplication_ignoresCurrentProcess() async {
        await MainActor.run {
            let currentApp = MockRunningApplication(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            )
            let uiState = AppUIState()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(
                    frontmostApplication: currentApp
                ),
                directPasteService: MockDirectPasteService(),
                uiState: uiState
            )

            delegate.captureRestoreTargetApplication()

            XCTAssertNil(delegate.restoreTargetApplication)
        }
    }

    func test_cancelledPopover_restoresFocusWithoutPasting() async {
        await MainActor.run {
            let frontmostApp = MockRunningApplication(
                bundleIdentifier: "com.example.notes",
                processIdentifier: 999
            )
            let directPasteService = MockDirectPasteService()
            let presenter = MockItemPreviewPresenter()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(
                    frontmostApplication: frontmostApp
                ),
                directPasteService: directPasteService,
                uiState: AppUIState(),
                previewPresenter: presenter
            )

            delegate.captureRestoreTargetApplication()
            delegate.handleCancelledPopoverForTesting()

            XCTAssertTrue(frontmostApp.didActivate)
            XCTAssertEqual(frontmostApp.activationOptions, [])
            XCTAssertEqual(presenter.closeCallCount, 1)
            XCTAssertEqual(directPasteService.permissionRequestCount, 0)
            XCTAssertNil(directPasteService.lastApplication)
        }
    }

    func test_applicationDidResignActive_marksHistoryPanelHidden() async {
        await MainActor.run {
            let uiState = AppUIState()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: MockDirectPasteService(),
                uiState: uiState
            )

            uiState.markHistoryPopoverPresented()
            delegate.applicationDidResignActive(
                Notification(name: NSApplication.didResignActiveNotification)
            )

            XCTAssertFalse(uiState.isHistoryPopoverVisible)
        }
    }

    func test_historyPanelFrame_fillsWidthAndTouchesBottom() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_200, height: 1_000)

        let frame = ClipboardHistoryPanelLayout.frame(in: visibleFrame)

        XCTAssertEqual(frame.minX, visibleFrame.minX)
        XCTAssertEqual(frame.minY, visibleFrame.minY)
        XCTAssertEqual(frame.width, visibleFrame.width)
        XCTAssertEqual(frame.height, 200)
    }

    func test_historyPanelFrame_usesMinimumHeightOnShortScreens() {
        let visibleFrame = CGRect(x: 80, y: 25, width: 600, height: 700)

        let frame = ClipboardHistoryPanelLayout.frame(in: visibleFrame)

        XCTAssertEqual(frame.height, ClipboardHistoryPanelLayout.minimumHeight)
    }

    func test_historyPanelFrame_capsHeightOnTallScreensWithoutCappingWidth() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 3_000, height: 2_000)

        let frame = ClipboardHistoryPanelLayout.frame(in: visibleFrame)

        XCTAssertEqual(frame.height, ClipboardHistoryPanelLayout.maximumHeight)
        XCTAssertEqual(frame.width, visibleFrame.width)
    }

    func test_batchPanelHeight_growsWithItemsAndCapsAtSixtyPercent() {
        XCTAssertEqual(
            BatchPastePanelLayout.preferredHeight(
                itemCount: 0,
                showsWarning: false,
                visibleScreenHeight: 1_000
            ),
            BatchPastePanelLayout.headerHeight + BatchPastePanelLayout.emptyStateHeight
        )
        XCTAssertEqual(
            BatchPastePanelLayout.preferredHeight(
                itemCount: 3,
                showsWarning: false,
                visibleScreenHeight: 1_000
            ),
            BatchPastePanelLayout.headerHeight + 3 * BatchPastePanelLayout.rowHeight
        )
        XCTAssertEqual(
            BatchPastePanelLayout.preferredHeight(
                itemCount: 200,
                showsWarning: true,
                visibleScreenHeight: 1_000
            ),
            600
        )
    }

    func test_batchPanelFrame_isClampedFullyInsideVisibleScreen() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_000, height: 700)
        let frame = CGRect(x: 950, y: -100, width: 320, height: 500)

        let result = BatchPastePanelLayout.clamped(frame, to: visibleFrame)

        XCTAssertEqual(result.maxX, visibleFrame.maxX)
        XCTAssertEqual(result.minY, visibleFrame.minY)
    }

    func test_batchPanelDraggedOrigin_tracksMouseDelta() {
        let result = BatchPastePanelLayout.draggedOrigin(
            windowOrigin: CGPoint(x: 1_000, y: 600),
            mouseDownLocation: CGPoint(x: 1_200, y: 800),
            currentMouseLocation: CGPoint(x: 1_135, y: 842)
        )

        XCTAssertEqual(result, CGPoint(x: 935, y: 642))
    }

    func test_batchPasteHotKey_waitsForReleaseBeforeStartingSelectionCapture() async {
        await MainActor.run {
            XCTAssertEqual(
                AppDelegate.globalHotKeyAction(
                    hotKeyID: 2,
                    eventKind: UInt32(kEventHotKeyPressed)
                ),
                .none
            )
            XCTAssertEqual(
                AppDelegate.globalHotKeyAction(
                    hotKeyID: 2,
                    eventKind: UInt32(kEventHotKeyReleased)
                ),
                .startBatchPaste
            )
        }
    }

    func test_historyHotKey_stillOpensOnPressAndIgnoresRelease() async {
        await MainActor.run {
            XCTAssertEqual(
                AppDelegate.globalHotKeyAction(
                    hotKeyID: 1,
                    eventKind: UInt32(kEventHotKeyPressed)
                ),
                .toggleHistory
            )
            XCTAssertEqual(
                AppDelegate.globalHotKeyAction(
                    hotKeyID: 1,
                    eventKind: UInt32(kEventHotKeyReleased)
                ),
                .none
            )
        }
    }

    func test_batchPasteCommand_consumesPreferredItemBeforePasting() async {
        await MainActor.run {
            let target = MockRunningApplication(
                bundleIdentifier: "com.example.notes",
                processIdentifier: 999
            )
            let directPasteService = MockDirectPasteService()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(
                    frontmostApplication: target
                ),
                directPasteService: directPasteService,
                uiState: AppUIState()
            )
            let first = FreePaste.ClipboardItem(content: .text("A"))
            let second = FreePaste.ClipboardItem(content: .text("B"))
            delegate.batchPasteSession.start(with: first)
            delegate.batchPasteSession.add(second)

            delegate.handleBatchPasteCommandForTesting(preferredItemID: second.id)

            XCTAssertEqual(delegate.batchPasteSession.items.map(\.id), [first.id])
            XCTAssertEqual(directPasteService.lastApplication?.processIdentifier, target.processIdentifier)
        }
    }

    func test_batchPasteCommand_withOnlyItem_pastesItAndEndsMode() async {
        await MainActor.run {
            let target = MockRunningApplication(
                bundleIdentifier: "com.example.notes",
                processIdentifier: 999
            )
            let directPasteService = MockDirectPasteService()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(
                    frontmostApplication: target
                ),
                directPasteService: directPasteService,
                uiState: AppUIState()
            )
            let onlyItem = FreePaste.ClipboardItem(content: .text("only"))
            delegate.batchPasteSession.start(with: onlyItem)

            delegate.handleBatchPasteCommandForTesting()

            XCTAssertFalse(delegate.batchPasteSession.isActive)
            XCTAssertEqual(directPasteService.lastApplication?.processIdentifier, target.processIdentifier)
        }
    }

    func test_applicationDidResignActive_closesPreview() async {
        await MainActor.run {
            let presenter = MockItemPreviewPresenter()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: MockDirectPasteService(),
                uiState: AppUIState(),
                previewPresenter: presenter
            )

            delegate.showPreviewOrToggle(FreePaste.ClipboardItem(content: .text("hello")))
            delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))

            XCTAssertFalse(presenter.isShowingPreview)
            XCTAssertEqual(presenter.closeCallCount, 1)
        }
    }

    func test_pasteBack_withoutTarget_returnsNoTargetApplication() async {
        await MainActor.run {
            let permissionController = MockAccessibilityPermissionController(isTrusted: true)
            let shortcutSender = MockPasteShortcutSender()
            let service = DirectPasteService(
                permissionController: permissionController,
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                shortcutSender: shortcutSender,
                activationDelay: 0,
                activationTimeout: 0,
                sleeper: { _ in }
            )

            let result = service.pasteBack(to: nil)

            assertResult(result, is: .noTargetApplication)
            XCTAssertEqual(permissionController.promptRequests, [])
            XCTAssertEqual(shortcutSender.sendCount, 0)
        }
    }

    // pasteBack trusts that the caller has already invoked requestAccessibilityPermissionIfNeeded().
    // Calling it without a pre-check still proceeds to activation — this test documents that contract.
    func test_pasteBack_doesNotCheckPermission_proceedsToActivation() async {
        await MainActor.run {
            let permissionController = MockAccessibilityPermissionController(isTrusted: false)
            let shortcutSender = MockPasteShortcutSender()
            let service = DirectPasteService(
                permissionController: permissionController,
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                shortcutSender: shortcutSender,
                activationDelay: 0,
                activationTimeout: 0,
                sleeper: { _ in }
            )
            let app = MockRunningApplication(bundleIdentifier: "com.example.notes", processIdentifier: 321)

            let result = service.pasteBack(to: app)

            // No permission check inside pasteBack — activation is attempted, then times out
            XCTAssertEqual(permissionController.promptRequests, [])
            XCTAssertTrue(app.didActivate)
            assertResult(result, is: .activationFailed)
            XCTAssertEqual(shortcutSender.sendCount, 0)
        }
    }

    func test_pasteBack_whenActivationFails_returnsActivationFailed() async {
        await MainActor.run {
            let permissionController = MockAccessibilityPermissionController(isTrusted: true)
            let shortcutSender = MockPasteShortcutSender()
            let service = DirectPasteService(
                permissionController: permissionController,
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                shortcutSender: shortcutSender,
                activationDelay: 0,
                activationTimeout: 0,
                sleeper: { _ in }
            )
            let app = MockRunningApplication(
                bundleIdentifier: "com.example.notes",
                processIdentifier: 321,
                activateReturnValue: false
            )

            let result = service.pasteBack(to: app)

            assertResult(result, is: .activationFailed)
            XCTAssertTrue(app.didActivate)
            XCTAssertEqual(shortcutSender.sendCount, 0)
        }
    }

    func test_pasteBack_whenShortcutDispatchSucceeds_returnsSuccess() async {
        await MainActor.run {
            let permissionController = MockAccessibilityPermissionController(isTrusted: true)
            let shortcutSender = MockPasteShortcutSender(sendResult: true)
            var sleptIntervals: [TimeInterval] = []
            let app = MockRunningApplication(bundleIdentifier: "com.example.notes", processIdentifier: 321)
            let service = DirectPasteService(
                permissionController: permissionController,
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: app),
                shortcutSender: shortcutSender,
                activationDelay: 0.12,
                activationTimeout: 0.2,
                sleeper: { sleptIntervals.append($0) }
            )

            let result = service.pasteBack(to: app)

            assertResult(result, is: .success)
            XCTAssertTrue(app.didActivate)
            XCTAssertEqual(app.activationOptions, [])
            XCTAssertEqual(sleptIntervals, [0.12])
            XCTAssertEqual(shortcutSender.sendCount, 1)
        }
    }

    func test_pasteBack_whenTargetNeverBecomesFrontmost_returnsActivationFailed() async {
        await MainActor.run {
            let permissionController = MockAccessibilityPermissionController(isTrusted: true)
            let shortcutSender = MockPasteShortcutSender(sendResult: true)
            var sleptIntervals: [TimeInterval] = []
            let app = MockRunningApplication(bundleIdentifier: "com.example.notes", processIdentifier: 321)
            let service = DirectPasteService(
                permissionController: permissionController,
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                shortcutSender: shortcutSender,
                activationDelay: 0.12,
                activationTimeout: 0.05,
                sleeper: { sleptIntervals.append($0) }
            )

            let result = service.pasteBack(to: app)

            assertResult(result, is: .activationFailed)
            XCTAssertTrue(app.didActivate)
            XCTAssertEqual(shortcutSender.sendCount, 0)
            XCTAssertFalse(sleptIntervals.isEmpty)
        }
    }

    func test_requestAccessibilityPermissionIfNeeded_checksQuietlyWithoutPrompt() async {
        await MainActor.run {
            let permissionController = MockAccessibilityPermissionController(isTrusted: false)
            let service = DirectPasteService(
                permissionController: permissionController,
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                shortcutSender: MockPasteShortcutSender(),
                activationDelay: 0,
                activationTimeout: 0,
                sleeper: { _ in }
            )

            let isTrusted = service.requestAccessibilityPermissionIfNeeded()

            XCTAssertFalse(isTrusted)
            // Should check quietly (promptIfNeeded: false) — in-app UI guides user to System Settings instead.
            XCTAssertEqual(permissionController.promptRequests, [false])
        }
    }

    func test_handleConfirmedItem_withoutPermission_keepsInlineMessage() async {
        await MainActor.run {
            let directPasteService = MockDirectPasteService()
            directPasteService.permissionGranted = false
            let uiState = AppUIState()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: directPasteService,
                uiState: uiState
            )

            delegate.captureRestoreTargetApplication()
            delegate.handleConfirmedItemForTesting(
                FreePaste.ClipboardItem(content: FreePaste.ClipboardContent.text("hello"))
            )

            XCTAssertEqual(directPasteService.permissionRequestCount, 1)
            XCTAssertEqual(uiState.inlineMessage?.text, "需要开启辅助功能权限后才能直接粘贴。授权后请重试。")
            XCTAssertEqual(uiState.inlineMessage?.action?.title, "去授权")
        }
    }

    func test_permissionInlineAction_opensAccessibilitySettings() async {
        await MainActor.run {
            let directPasteService = MockDirectPasteService()
            directPasteService.permissionGranted = false
            let settingsOpener = MockSystemSettingsOpener()
            let uiState = AppUIState()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: directPasteService,
                systemSettingsOpener: settingsOpener,
                uiState: uiState
            )

            delegate.handleConfirmedItemForTesting(
                FreePaste.ClipboardItem(content: FreePaste.ClipboardContent.text("hello"))
            )

            uiState.inlineMessage?.action?.perform()

            XCTAssertEqual(settingsOpener.openAccessibilitySettingsCount, 1)
        }
    }

    func test_showPreviewOrToggle_opensPreviewForItem() async {
        await MainActor.run {
            let presenter = MockItemPreviewPresenter()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: MockDirectPasteService(),
                uiState: AppUIState(),
                previewPresenter: presenter
            )
            let item = FreePaste.ClipboardItem(content: .text("hello"))

            delegate.showPreviewOrToggle(item)

            XCTAssertTrue(presenter.isShowingPreview)
            XCTAssertEqual(presenter.previewItemID, item.id)
            XCTAssertEqual(presenter.showCalls.count, 1)
        }
    }

    func test_showPreviewOrToggle_sameItem_closesPreview() async {
        await MainActor.run {
            let presenter = MockItemPreviewPresenter()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: MockDirectPasteService(),
                uiState: AppUIState(),
                previewPresenter: presenter
            )
            let item = FreePaste.ClipboardItem(content: .text("hello"))

            delegate.showPreviewOrToggle(item)
            delegate.showPreviewOrToggle(item)

            XCTAssertFalse(presenter.isShowingPreview)
            XCTAssertEqual(presenter.showCalls.count, 1)
            XCTAssertEqual(presenter.closeCallCount, 1)
        }
    }

    func test_showPreviewOrToggle_differentItem_replacesPreview() async {
        await MainActor.run {
            let presenter = MockItemPreviewPresenter()
            let delegate = AppDelegate(
                frontmostApplicationProvider: MockFrontmostApplicationProvider(frontmostApplication: nil),
                directPasteService: MockDirectPasteService(),
                uiState: AppUIState(),
                previewPresenter: presenter
            )
            let item1 = FreePaste.ClipboardItem(content: .text("hello"))
            let item2 = FreePaste.ClipboardItem(content: .text("world"))

            delegate.showPreviewOrToggle(item1)
            delegate.showPreviewOrToggle(item2)

            XCTAssertTrue(presenter.isShowingPreview)
            XCTAssertEqual(presenter.previewItemID, item2.id)
            XCTAssertEqual(presenter.showCalls.count, 2)
            XCTAssertEqual(presenter.closeCallCount, 1)
        }
    }

    private func assertResult(_ result: DirectPasteResult, is expected: DirectPasteResult) {
        switch (result, expected) {
        case (.success, .success),
             (.noTargetApplication, .noTargetApplication),
             (.missingAccessibilityPermission, .missingAccessibilityPermission),
             (.activationFailed, .activationFailed),
             (.eventDispatchFailed, .eventDispatchFailed):
            return
        default:
            XCTFail("Unexpected result: \(String(describing: result)) expected \(String(describing: expected))")
        }
    }
}

private final class MockRunningApplication: RunningApplication {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let activateReturnValue: Bool

    private(set) var didActivate = false
    private(set) var activationOptions: NSApplication.ActivationOptions = []

    init(
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        activateReturnValue: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.activateReturnValue = activateReturnValue
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        didActivate = true
        activationOptions = options
        return activateReturnValue
    }
}

private struct MockFrontmostApplicationProvider: FrontmostApplicationProviding {
    let frontmostApplication: (any RunningApplication)?
}

private final class MockDirectPasteService: DirectPasteServicing {
    private(set) var lastApplication: (any RunningApplication)?
    var permissionGranted = true
    private(set) var permissionRequestCount = 0

    func requestAccessibilityPermissionIfNeeded() -> Bool {
        permissionRequestCount += 1
        return permissionGranted
    }

    @discardableResult
    func pasteBack(to application: (any RunningApplication)?) -> DirectPasteResult {
        lastApplication = application
        return .success
    }
}

private final class MockAccessibilityPermissionController: AccessibilityPermissionControlling {
    let isTrustedValue: Bool
    private(set) var promptRequests: [Bool] = []

    init(isTrusted: Bool) {
        isTrustedValue = isTrusted
    }

    func isTrusted(promptIfNeeded: Bool) -> Bool {
        promptRequests.append(promptIfNeeded)
        return isTrustedValue
    }
}

private final class MockSystemSettingsOpener: SystemSettingsOpening {
    private(set) var openAccessibilitySettingsCount = 0
    private(set) var openInputMonitoringSettingsCount = 0
    var openAccessibilitySettingsReturnValue = true
    var openInputMonitoringSettingsReturnValue = true

    func openAccessibilitySettings() -> Bool {
        openAccessibilitySettingsCount += 1
        return openAccessibilitySettingsReturnValue
    }

    func openInputMonitoringSettings() -> Bool {
        openInputMonitoringSettingsCount += 1
        return openInputMonitoringSettingsReturnValue
    }
}

private final class MockItemPreviewPresenter: ItemPreviewPresenting {
    private(set) var previewItemID: FreePaste.ClipboardItem.ID?
    private(set) var isShowingPreview = false
    private(set) var showCalls: [FreePaste.ClipboardItem] = []
    private(set) var closeCallCount = 0

    func showPreview(for item: FreePaste.ClipboardItem, nearWindow: NSWindow?) {
        showCalls.append(item)
        isShowingPreview = true
        previewItemID = item.id
    }

    func closePreview() {
        closeCallCount += 1
        isShowingPreview = false
        previewItemID = nil
    }
}

private final class MockPasteShortcutSender: PasteShortcutSending {
    let sendResult: Bool
    private(set) var sendCount = 0

    init(sendResult: Bool = true) {
        self.sendResult = sendResult
    }

    func sendPasteShortcut() -> Bool {
        sendCount += 1
        return sendResult
    }
}
