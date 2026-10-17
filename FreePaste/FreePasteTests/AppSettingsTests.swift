//
//  AppSettingsTests.swift
//  FreePasteTests
//
//  Created by Codex on 2026/3/16.
//

import Carbon.HIToolbox
import XCTest

@testable import FreePaste

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var launchAtLoginController: MockLaunchAtLoginController!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        launchAtLoginController = MockLaunchAtLoginController()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        launchAtLoginController = nil
        super.tearDown()
    }

    func test_init_usesDefaultsWhenUnset() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        XCTAssertEqual(settings.maxItems, 0)
        XCTAssertEqual(settings.visibleHistoryItemCount, 5)
        XCTAssertTrue(settings.autoPreviewEnabled)
        XCTAssertEqual(settings.maxTotalSizeMB, 0)
        XCTAssertEqual(settings.retentionDays, 0)
        XCTAssertTrue(settings.deduplicateEnabled)
        XCTAssertEqual(settings.recordingPauseState, .active)
        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertEqual(settings.nextItemShortcut, .defaultNextItem)
        XCTAssertEqual(settings.previousItemShortcut, .defaultPreviousItem)
        XCTAssertEqual(settings.deleteSelectedItemShortcut, .defaultDeleteSelectedItem)
        XCTAssertEqual(settings.focusSearchShortcut, .defaultFocusSearch)
        XCTAssertEqual(settings.switchPanelShortcut, .defaultSwitchPanel)
        XCTAssertEqual(settings.togglePinShortcut, .defaultTogglePin)
        XCTAssertEqual(settings.plainTextPasteShortcut, .defaultPlainTextPaste)
        XCTAssertEqual(settings.previewShortcut, KeyboardShortcut(keyCode: UInt16(kVK_Space)))
        XCTAssertEqual(settings.batchPasteStartShortcut, .defaultBatchPasteStart)
        XCTAssertEqual(settings.batchPasteDirection, .forward)
        XCTAssertEqual(
            settings.plainTextPasteShortcut,
            KeyboardShortcut(keyCode: UInt16(kVK_Return), modifierFlags: .shift)
        )
        XCTAssertEqual(
            settings.nextItemShortcut,
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_F), modifierFlags: .control)
        )
        XCTAssertEqual(
            settings.previousItemShortcut,
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_B), modifierFlags: .control)
        )
        XCTAssertEqual(
            settings.focusSearchShortcut,
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_F), modifierFlags: .command)
        )
        XCTAssertEqual(
            settings.deleteSelectedItemShortcut,
            KeyboardShortcut(keyCode: UInt16(kVK_Delete), modifierFlags: .command)
        )
    }

    func test_init_migratesLegacySearchAndDeleteShortcutsWithoutRepeatingMigration() throws {
        let slash = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Slash))
        let backspace = KeyboardShortcut(keyCode: UInt16(kVK_Delete))
        defaults.set(try JSONEncoder().encode(slash), forKey: AppSettings.Keys.focusSearchShortcut)
        defaults.set(try JSONEncoder().encode(backspace), forKey: AppSettings.Keys.deleteSelectedItemShortcut)

        let settings = AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController)

        XCTAssertEqual(settings.focusSearchShortcut, .defaultFocusSearch)
        XCTAssertEqual(settings.deleteSelectedItemShortcut, .defaultDeleteSelectedItem)
        XCTAssertEqual(
            try JSONDecoder().decode(KeyboardShortcut.self, from: XCTUnwrap(defaults.data(forKey: AppSettings.Keys.focusSearchShortcut))),
            .defaultFocusSearch
        )
        XCTAssertEqual(
            try JSONDecoder().decode(KeyboardShortcut.self, from: XCTUnwrap(defaults.data(forKey: AppSettings.Keys.deleteSelectedItemShortcut))),
            .defaultDeleteSelectedItem
        )

        let customSearch = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.command, .option])
        let customDelete = KeyboardShortcut(keyCode: UInt16(kVK_ForwardDelete), modifierFlags: .control)
        settings.focusSearchShortcut = customSearch
        settings.deleteSelectedItemShortcut = customDelete
        let reloaded = AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController)
        XCTAssertEqual(reloaded.focusSearchShortcut, customSearch)
        XCTAssertEqual(reloaded.deleteSelectedItemShortcut, customDelete)
    }

    func test_init_preservesCustomizedSearchAndDeleteShortcutsDuringMigration() throws {
        let search = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.command, .option])
        let delete = KeyboardShortcut(keyCode: UInt16(kVK_ForwardDelete))
        defaults.set(try JSONEncoder().encode(search), forKey: AppSettings.Keys.focusSearchShortcut)
        defaults.set(try JSONEncoder().encode(delete), forKey: AppSettings.Keys.deleteSelectedItemShortcut)

        let settings = AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController)

        XCTAssertEqual(settings.focusSearchShortcut, search)
        XCTAssertEqual(settings.deleteSelectedItemShortcut, delete)
    }

    func test_conflictChecker_reservesQuickSearchEditingAndScopeKeys() {
        let settings = AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController)
        settings.focusSearchShortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: .command)
        settings.switchPanelShortcut = KeyboardShortcut(keyCode: UInt16(kVK_Tab), modifierFlags: .option)

        XCTAssertEqual(settings.conflictingActionName(for: .defaultFocusSearch, excludingName: "下一项"), "聚焦搜索栏")
        XCTAssertEqual(settings.conflictingActionName(for: .defaultSwitchPanel, excludingName: "下一项"), "切换最近/收藏")
        XCTAssertEqual(settings.conflictingActionName(
            for: KeyboardShortcut(keyCode: UInt16(kVK_Delete)), excludingName: "删除选中项"
        ), "搜索文本退格")
        XCTAssertNil(settings.conflictingActionName(for: .defaultFocusSearch, excludingName: "聚焦搜索栏"))
        XCTAssertNil(settings.conflictingActionName(for: .defaultSwitchPanel, excludingName: "切换最近/收藏"))
    }

    func test_init_migratesLegacyNavigationShortcutsToControlFAndB() throws {
        let legacyNext = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_N),
            modifierFlags: .control
        )
        let legacyPrevious = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_P),
            modifierFlags: .control
        )
        defaults.set(
            try JSONEncoder().encode(legacyNext),
            forKey: AppSettings.Keys.nextItemShortcut
        )
        defaults.set(
            try JSONEncoder().encode(legacyPrevious),
            forKey: AppSettings.Keys.previousItemShortcut
        )

        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        XCTAssertEqual(settings.nextItemShortcut, .defaultNextItem)
        XCTAssertEqual(settings.previousItemShortcut, .defaultPreviousItem)
        XCTAssertEqual(
            try JSONDecoder().decode(
                KeyboardShortcut.self,
                from: XCTUnwrap(defaults.data(forKey: AppSettings.Keys.nextItemShortcut))
            ),
            .defaultNextItem
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                KeyboardShortcut.self,
                from: XCTUnwrap(defaults.data(forKey: AppSettings.Keys.previousItemShortcut))
            ),
            .defaultPreviousItem
        )

        settings.nextItemShortcut = legacyNext
        settings.previousItemShortcut = legacyPrevious
        let reloaded = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )
        XCTAssertEqual(reloaded.nextItemShortcut, legacyNext)
        XCTAssertEqual(reloaded.previousItemShortcut, legacyPrevious)
    }

    func test_init_preservesCustomizedNavigationShortcutsDuringMigration() throws {
        let customNext = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_J),
            modifierFlags: .control
        )
        let customPrevious = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: .control
        )
        defaults.set(
            try JSONEncoder().encode(customNext),
            forKey: AppSettings.Keys.nextItemShortcut
        )
        defaults.set(
            try JSONEncoder().encode(customPrevious),
            forKey: AppSettings.Keys.previousItemShortcut
        )

        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        XCTAssertEqual(settings.nextItemShortcut, customNext)
        XCTAssertEqual(settings.previousItemShortcut, customPrevious)
    }

    func test_changes_arePersistedToUserDefaults() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        settings.maxItems = 42
        settings.visibleHistoryItemCount = 9
        settings.autoPreviewEnabled = false
        settings.maxTotalSizeMB = 64
        settings.retentionDays = 30
        settings.deduplicateEnabled = false
        settings.pauseRecordingManually()
        settings.nextItemShortcut = KeyboardShortcut(keyCode: 38, modifierFlags: .control)
        settings.previousItemShortcut = KeyboardShortcut(keyCode: 40, modifierFlags: .control)
        settings.deleteSelectedItemShortcut = KeyboardShortcut(keyCode: 117)
        settings.focusSearchShortcut = KeyboardShortcut(keyCode: 44, modifierFlags: .command)
        settings.switchPanelShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: .option)
        settings.batchPasteStartShortcut = KeyboardShortcut(keyCode: 8, modifierFlags: [.command, .option])
        settings.batchPasteDirection = .reverse
        settings.previewShortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_P), modifierFlags: [.command, .option])

        let reloaded = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )
        XCTAssertEqual(reloaded.maxItems, 42)
        XCTAssertEqual(reloaded.visibleHistoryItemCount, 9)
        XCTAssertFalse(reloaded.autoPreviewEnabled)
        XCTAssertEqual(reloaded.maxTotalSizeMB, 64)
        XCTAssertEqual(reloaded.retentionDays, 30)
        XCTAssertFalse(reloaded.deduplicateEnabled)
        XCTAssertEqual(reloaded.recordingPauseState, .pausedManually)
        XCTAssertEqual(reloaded.nextItemShortcut, KeyboardShortcut(keyCode: 38, modifierFlags: .control))
        XCTAssertEqual(reloaded.previousItemShortcut, KeyboardShortcut(keyCode: 40, modifierFlags: .control))
        XCTAssertEqual(reloaded.deleteSelectedItemShortcut, KeyboardShortcut(keyCode: 117))
        XCTAssertEqual(reloaded.focusSearchShortcut, KeyboardShortcut(keyCode: 44, modifierFlags: .command))
        XCTAssertEqual(reloaded.switchPanelShortcut, KeyboardShortcut(keyCode: 48, modifierFlags: .option))
        XCTAssertEqual(
            reloaded.batchPasteStartShortcut,
            KeyboardShortcut(keyCode: 8, modifierFlags: [.command, .option])
        )
        XCTAssertEqual(reloaded.batchPasteDirection, .reverse)
        XCTAssertEqual(
            reloaded.previewShortcut,
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_P), modifierFlags: [.command, .option])
        )
    }

    func test_init_migratesLegacyPlainTextPasteShortcutToShiftReturn() throws {
        let legacyShortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_Return),
            modifierFlags: .option
        )
        defaults.set(
            try JSONEncoder().encode(legacyShortcut),
            forKey: AppSettings.Keys.plainTextPasteShortcut
        )

        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        XCTAssertEqual(settings.plainTextPasteShortcut, .defaultPlainTextPaste)
        let storedData = try XCTUnwrap(
            defaults.data(forKey: AppSettings.Keys.plainTextPasteShortcut)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(KeyboardShortcut.self, from: storedData),
            .defaultPlainTextPaste
        )

        settings.plainTextPasteShortcut = legacyShortcut
        let reloaded = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )
        XCTAssertEqual(reloaded.plainTextPasteShortcut, legacyShortcut)
    }

    func test_init_preservesCustomizedPlainTextPasteShortcutDuringMigration() throws {
        let customShortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_Return),
            modifierFlags: [.command, .shift]
        )
        defaults.set(
            try JSONEncoder().encode(customShortcut),
            forKey: AppSettings.Keys.plainTextPasteShortcut
        )

        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        XCTAssertEqual(settings.plainTextPasteShortcut, customShortcut)
    }

    func test_init_reflectsCurrentLaunchAtLoginState() {
        launchAtLoginController.isEnabled = true

        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        XCTAssertTrue(settings.launchAtLoginEnabled)
    }

    func test_launchAtLoginToggle_updatesController() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        settings.launchAtLoginEnabled = true

        XCTAssertEqual(launchAtLoginController.setEnabledCalls, [true])
        XCTAssertNil(settings.launchAtLoginErrorMessage)
    }

    func test_launchAtLoginToggle_failure_revertsStateAndExposesError() {
        launchAtLoginController.error = NSError(domain: "test", code: 1)
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        settings.launchAtLoginEnabled = true

        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertEqual(settings.launchAtLoginErrorMessage, "无法更新开机自启，请稍后重试。")
    }

    func test_restoreDefaultShortcuts_resetsAllShortcutSettings() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )
        settings.nextItemShortcut = KeyboardShortcut(keyCode: 38, modifierFlags: .control)
        settings.previousItemShortcut = KeyboardShortcut(keyCode: 40, modifierFlags: .control)
        settings.deleteSelectedItemShortcut = KeyboardShortcut(keyCode: 117)
        settings.focusSearchShortcut = KeyboardShortcut(keyCode: 44, modifierFlags: .command)
        settings.batchPasteStartShortcut = KeyboardShortcut(keyCode: 8, modifierFlags: .control)
        settings.plainTextPasteShortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_Return),
            modifierFlags: .option
        )
        settings.previewShortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_P), modifierFlags: [.control, .shift])

        settings.restoreDefaultShortcuts()

        XCTAssertEqual(settings.nextItemShortcut, .defaultNextItem)
        XCTAssertEqual(settings.previousItemShortcut, .defaultPreviousItem)
        XCTAssertEqual(settings.deleteSelectedItemShortcut, .defaultDeleteSelectedItem)
        XCTAssertEqual(settings.focusSearchShortcut, .defaultFocusSearch)
        XCTAssertEqual(settings.batchPasteStartShortcut, .defaultBatchPasteStart)
        XCTAssertEqual(settings.plainTextPasteShortcut, .defaultPlainTextPaste)
        XCTAssertEqual(settings.previewShortcut, .defaultPreview)
        XCTAssertEqual(
            AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController).previewShortcut,
            .defaultPreview
        )
    }

    func test_previewShortcut_conflictsWithOtherActionsButNotItself() {
        let settings = AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController)
        XCTAssertEqual(settings.conflictingActionName(for: .defaultPreview, excludingName: "下一项"), "预览/关闭预览")
        XCTAssertNil(settings.conflictingActionName(for: .defaultPreview, excludingName: "预览/关闭预览"))

        let custom = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_P), modifierFlags: [.command, .option])
        settings.previewShortcut = custom

        XCTAssertEqual(settings.conflictingActionName(for: custom, excludingName: "聚焦搜索栏"), "预览/关闭预览")
        XCTAssertNil(settings.conflictingActionName(for: custom, excludingName: "预览/关闭预览"))
        XCTAssertNil(settings.conflictingActionName(for: .defaultPreview, excludingName: "下一项"))
        XCTAssertEqual(settings.conflictingActionName(for: settings.nextItemShortcut, excludingName: "预览/关闭预览"), "下一项")
        XCTAssertEqual(settings.conflictingActionName(for: .defaultFocusSearch, excludingName: "预览/关闭预览"), "聚焦搜索栏")
    }

    func test_previewShortcut_invalidSavedValueFallsBackWithoutChangingOtherBindings() throws {
        let customNext = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_J), modifierFlags: .control)
        defaults.set(try JSONEncoder().encode(customNext), forKey: AppSettings.Keys.nextItemShortcut)
        defaults.set(Data([0xFF]), forKey: AppSettings.Keys.previewShortcut)

        let settings = AppSettings(defaults: defaults, launchAtLoginController: launchAtLoginController)

        XCTAssertEqual(settings.previewShortcut, .defaultPreview)
        XCTAssertEqual(settings.nextItemShortcut, customNext)
    }

    func test_visibleHistoryItemCount_isClampedToSupportedRange() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        settings.visibleHistoryItemCount = 1
        XCTAssertEqual(settings.visibleHistoryItemCount, 3)

        settings.visibleHistoryItemCount = 99
        XCTAssertEqual(settings.visibleHistoryItemCount, 20)
    }

    func test_conflictingActionName_reservesCommandVForBatchPaste() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        let conflict = settings.conflictingActionName(
            for: KeyboardShortcut(keyCode: 9, modifierFlags: .command),
            excludingName: "启动批量收集"
        )

        XCTAssertEqual(conflict, "批量模式粘贴")
    }

    func test_effectiveRecordingPauseState_expiresTimedPause() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )
        settings.recordingPauseState = .pausedUntil(Date(timeIntervalSinceNow: -1))

        let resolved = settings.effectiveRecordingPauseState

        XCTAssertEqual(resolved, .active)
        XCTAssertEqual(settings.recordingPauseState, .active)
    }

    func test_pauseRecording_forDuration_setsTimedPauseState() {
        let settings = AppSettings(
            defaults: defaults,
            launchAtLoginController: launchAtLoginController
        )

        settings.pauseRecording(for: 5 * 60)

        switch settings.recordingPauseState {
        case .pausedUntil(let deadline):
            XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 0)
        default:
            XCTFail("Expected a timed pause state")
        }
    }
}

private final class MockLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled = false
    var error: Error?
    var setEnabledCalls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let error {
            throw error
        }
        isEnabled = enabled
    }
}
