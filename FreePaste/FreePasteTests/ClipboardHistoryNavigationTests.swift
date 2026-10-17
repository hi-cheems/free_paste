//
//  ClipboardHistoryNavigationTests.swift
//  FreePasteTests
//
//  Created by Codex on 2026/3/15.
//

import XCTest
import Carbon.HIToolbox
import AppKit

@testable import FreePaste

final class ClipboardHistoryNavigationTests: XCTestCase {

    private var routingDefaultsSuiteNames: [String] = []

    override func tearDown() {
        routingDefaultsSuiteNames.forEach {
            UserDefaults(suiteName: $0)?.removePersistentDomain(forName: $0)
        }
        routingDefaultsSuiteNames.removeAll()
        super.tearDown()
    }

    func test_selectionScrollDoesNotForceSelectedItemToCenter() {
        XCTAssertNil(ClipboardHistorySelectionScrollBehavior.anchor)
    }

    func test_resetSelection_selectsFirstItem() {
        var navigation = ClipboardHistoryNavigation<Int>()

        navigation.resetSelection(itemIDs: [10, 20, 30])

        XCTAssertEqual(navigation.selectedItemID, 10)
    }

    func test_resetSelection_preservesVisibleSelection() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(20)

        navigation.resetSelection(itemIDs: [10, 20, 30])

        XCTAssertEqual(navigation.selectedItemID, 20)
    }

    func test_prepareForPresentation_selectsFirstItemAndEnablesQuickSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()

        navigation.prepareForPresentation(itemIDs: [10, 20, 30])

        XCTAssertEqual(navigation.selectedItemID, 10)
        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertTrue(navigation.shouldHandlePanelKeyEvent())
    }

    func test_prepareForPresentation_withEmptyListStillUsesQuickSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()

        navigation.prepareForPresentation(itemIDs: [])

        XCTAssertNil(navigation.selectedItemID)
        XCTAssertEqual(navigation.searchMode, .quick)
    }

    func test_editingSearch_routesKeyboardEventsAwayFromPanelCommands() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.prepareForPresentation(itemIDs: [10])

        navigation.beginEditingSearch()

        XCTAssertFalse(navigation.shouldHandlePanelKeyEvent())
    }

    func test_selectFirst_overridesVisibleSelection() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(20)

        navigation.selectFirst(itemIDs: [10, 20, 30])

        XCTAssertEqual(navigation.selectedItemID, 10)
    }

    func test_selectFirst_preservesSearchFocus() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(20)
        navigation.beginEditingSearch()

        navigation.selectFirst(itemIDs: [10, 20, 30])

        XCTAssertEqual(navigation.selectedItemID, 10)
        XCTAssertEqual(navigation.searchMode, .editing)
    }

    func test_moveInQuickSearch_advancesSelectionWithoutAnExtraFocusStep() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2, 3])

        let handled = navigation.move(step: 1, itemIDs: [1, 2, 3])

        XCTAssertTrue(handled)
        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertEqual(navigation.selectedItemID, 2)
    }

    func test_moveWithinList_updatesSelectionWithoutWrapping() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2, 3])
        navigation.select(2)

        _ = navigation.move(step: 1, itemIDs: [1, 2, 3])
        XCTAssertEqual(navigation.selectedItemID, 3)

        _ = navigation.move(step: 1, itemIDs: [1, 2, 3])
        XCTAssertEqual(navigation.selectedItemID, 3)

        _ = navigation.move(step: -5, itemIDs: [1, 2, 3])
        XCTAssertEqual(navigation.selectedItemID, 1)
    }

    func test_editingSearch_navigationKeysDoNotExitEditingOrChangeSelection() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2])
        navigation.beginEditingSearch()

        XCTAssertFalse(navigation.move(step: 1, itemIDs: [1, 2]))
        XCTAssertFalse(navigation.move(step: -1, itemIDs: [1, 2]))
        XCTAssertNil(navigation.deleteSelectedItem(in: [1, 2]))
        XCTAssertNil(navigation.confirmedItemID(in: [1, 2]))
        XCTAssertEqual(navigation.searchMode, .editing)
        XCTAssertEqual(navigation.selectedItemID, 1)
    }

    func test_selectingRecordWithMouse_doesNotExitEditingSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.beginEditingSearch()
        navigation.resetSelection(itemIDs: [1, 2])
        navigation.select(2)

        XCTAssertEqual(navigation.searchMode, .editing)
        XCTAssertEqual(navigation.selectedItemID, 2)
    }

    func test_exitEditingSearch_selectsFirstVisibleItemAndEnablesQuickSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.beginEditingSearch()

        navigation.exitSearch(itemIDs: [1, 2])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertEqual(navigation.selectedItemID, 1)
    }

    func test_exitEditingSearch_preservesVisibleSelection() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(2)
        navigation.beginEditingSearch()

        navigation.exitSearch(itemIDs: [1, 2, 3])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertEqual(navigation.selectedItemID, 2)
    }

    func test_exitEditingSearch_withEmptyListStillReturnsToQuickSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()

        navigation.exitSearch(itemIDs: [])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertNil(navigation.selectedItemID)
    }

    func test_confirmedItemID_returnsNilWhenSelectionNotVisible() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(99)

        let confirmed = navigation.confirmedItemID(in: [1, 2, 3])

        XCTAssertNil(confirmed)
    }

    func test_confirmedItemID_returnsNilWhenSearchIsFocused() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(2)
        navigation.beginEditingSearch()

        let confirmed = navigation.confirmedItemID(in: [1, 2, 3])

        XCTAssertNil(confirmed)
    }

    func test_confirmedItemID_returnsSelectedVisibleItem() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(2)

        let confirmed = navigation.confirmedItemID(in: [1, 2, 3])

        XCTAssertEqual(confirmed, 2)
    }

    func test_deleteSelectedItem_returnsDeletedItemAndSelectsNextItem() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(2)

        let deleted = navigation.deleteSelectedItem(in: [1, 2, 3])

        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(navigation.selectedItemID, 3)
        XCTAssertEqual(navigation.searchMode, .quick)
    }

    func test_deleteSelectedItem_onLastItemSelectsPreviousItem() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(3)

        let deleted = navigation.deleteSelectedItem(in: [1, 2, 3])

        XCTAssertEqual(deleted, 3)
        XCTAssertEqual(navigation.selectedItemID, 2)
    }

    func test_deleteSelectedItem_whenListBecomesEmpty_retainsQuickSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(7)

        let deleted = navigation.deleteSelectedItem(in: [7])

        XCTAssertEqual(deleted, 7)
        XCTAssertNil(navigation.selectedItemID)
        XCTAssertEqual(navigation.searchMode, .quick)
    }

    // MARK: - 双面板切换

    func test_initialPanel_isRecent() {
        let navigation = ClipboardHistoryNavigation<Int>()

        XCTAssertEqual(navigation.activePanel, .recent)
    }

    func test_switchPanel_togglesToFavorites() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2])

        let panel = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])

        XCTAssertEqual(panel, .favorites)
        XCTAssertEqual(navigation.activePanel, .favorites)
    }

    func test_switchPanel_togglesBackToRecent() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2])
        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10])

        let panel = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10])

        XCTAssertEqual(panel, .recent)
    }

    func test_enterFavorites_keepsQuickSearchAndRecordNavigation() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.prepareForPresentation(itemIDs: [1, 2])

        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertEqual(navigation.selectedItemID, 10)
        XCTAssertTrue(navigation.shouldHandlePanelKeyEvent())
        XCTAssertTrue(navigation.move(step: 1, itemIDs: [10, 20]))
        XCTAssertEqual(navigation.confirmedItemID(in: [10, 20]), 20)
    }

    func test_returnToRecent_afterLeavingSearchRetainsListFocusAndSelection() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(2)
        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10])
        navigation.exitSearch(itemIDs: [10])

        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10])

        XCTAssertEqual(navigation.activePanel, .recent)
        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertEqual(navigation.selectedItemID, 2)
    }

    func test_switchPanel_selectsFirstItemOfTargetPanel() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2])

        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])

        XCTAssertEqual(navigation.selectedItemID, 10)
    }

    func test_switchPanel_preservesSelectionPerPanel() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1, 2, 3])
        navigation.select(3)

        _ = navigation.switchPanel(recentIDs: [1, 2, 3], favoriteIDs: [10, 20])
        // favorites panel: select 20
        navigation.select(20)

        // Switch back to recent
        _ = navigation.switchPanel(recentIDs: [1, 2, 3], favoriteIDs: [10, 20])
        XCTAssertEqual(navigation.selectedItemID, 3, "切回最近面板应恢复之前的选中项")

        // Switch to favorites again
        _ = navigation.switchPanel(recentIDs: [1, 2, 3], favoriteIDs: [10, 20])
        XCTAssertEqual(navigation.selectedItemID, 20, "切回收藏面板应恢复之前的选中项")
    }

    func test_switchPanel_toEmptyFavorites_keepsQuickSearch() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(1)

        _ = navigation.switchPanel(recentIDs: [1], favoriteIDs: [])

        XCTAssertNil(navigation.selectedItemID)
        XCTAssertEqual(navigation.searchMode, .quick)
    }

    func test_switchPanel_fromEditingSearch_preservesEditingMode() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.resetSelection(itemIDs: [1])
        navigation.beginEditingSearch()

        _ = navigation.switchPanel(recentIDs: [1], favoriteIDs: [10])

        XCTAssertEqual(navigation.selectedItemID, 10)
        XCTAssertEqual(navigation.searchMode, .editing)
    }

    func test_exitSearch_movesFocusToListAndSelectsFirstVisibleItem() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.beginEditingSearch()

        navigation.exitSearch(itemIDs: [10, 20])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertEqual(navigation.selectedItemID, 10)
    }

    func test_exitSearch_movesFocusToListWhenResultsAreEmpty() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.beginEditingSearch()

        navigation.exitSearch(itemIDs: [])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertNil(navigation.selectedItemID)
    }

    func test_fieldEditorRoutesOnlyEscapeToPanel() {
        XCTAssertTrue(
            KeyboardEventMonitor.shouldRouteToPanel(
                isFieldEditor: true,
                keyCode: UInt16(kVK_Escape)
            )
        )
        XCTAssertFalse(
            KeyboardEventMonitor.shouldRouteToPanel(
                isFieldEditor: true,
                keyCode: UInt16(kVK_Return)
            )
        )
        XCTAssertFalse(
            KeyboardEventMonitor.shouldRouteToPanel(
                isFieldEditor: true,
                keyCode: UInt16(kVK_Tab)
            )
        )
    }

    func test_quickSearch_routesNativeFieldEditorNavigationToPanel() {
        for keyCode in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Tab, kVK_Return, kVK_ANSI_F] {
            XCTAssertTrue(KeyboardEventMonitor.shouldRouteToPanel(
                isFieldEditor: true,
                keyCode: UInt16(keyCode),
                handlesFieldEditorEvents: true
            ))
        }
    }

    func test_markedText_keepsNavigationAndEscapeWithInputMethod() {
        for handlesFieldEditorEvents in [true, false] {
            for keyCode in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape, kVK_Return, kVK_Space] {
                XCTAssertFalse(KeyboardEventMonitor.shouldRouteToPanel(
                    isFieldEditor: true,
                    keyCode: UInt16(keyCode),
                    handlesFieldEditorEvents: handlesFieldEditorEvents,
                    hasMarkedText: true
                ))
            }
        }
    }

    func test_reopeningPanel_exitsEditingButRestoresVisibleSelection() {
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.select(2)
        navigation.beginEditingSearch()

        navigation.prepareForPresentation(itemIDs: [1, 2])

        XCTAssertEqual(navigation.searchMode, .quick)
        XCTAssertTrue(navigation.shouldHandlePanelKeyEvent())
        XCTAssertEqual(navigation.selectedItemID, 2)
    }

    func test_quickSearch_routesArrowsAndConfiguredNavigationWhileAcceptingText() throws {
        let settings = makeRoutingSettings()
        let nextKeys: [(Int, NSEvent.ModifierFlags)] = [(kVK_RightArrow, []), (kVK_DownArrow, []), (kVK_ANSI_F, .control)]
        let previousKeys: [(Int, NSEvent.ModifierFlags)] = [(kVK_LeftArrow, []), (kVK_UpArrow, []), (kVK_ANSI_B, .control)]
        for (key, modifiers) in nextKeys {
            XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(key, modifiers: modifiers), isEditingSearch: false, settings: settings), .nextItem)
        }
        for (key, modifiers) in previousKeys {
            XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(key, modifiers: modifiers), isEditingSearch: false, settings: settings), .previousItem)
        }
        for key in [kVK_ANSI_E, kVK_Delete, kVK_ANSI_Slash] {
            XCTAssertNil(ClipboardHistoryKeyAction.resolve(try keyEvent(key), isEditingSearch: false, settings: settings))
        }
        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Return), isEditingSearch: false, settings: settings), .paste)
        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Return, modifiers: .shift), isEditingSearch: false, settings: settings), .pastePlainText)
        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Delete, modifiers: .command), isEditingSearch: false, settings: settings), .deleteItem)
    }

    func test_quickSearch_spacePreviewsSelectedItemInHistoryAndFavorites() throws {
        let settings = makeRoutingSettings()
        let space = try keyEvent(kVK_Space)
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.prepareForPresentation(itemIDs: [1, 2])

        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(space, isEditingSearch: false, settings: settings), .preview)
        XCTAssertEqual(navigation.confirmedItemID(in: [1, 2]), 1)

        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])

        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(space, isEditingSearch: navigation.searchMode == .editing, settings: settings), .preview)
        XCTAssertEqual(navigation.confirmedItemID(in: [10, 20]), 10)
    }

    func test_quickSearch_modifiedSpaceStaysWithNativeInput() throws {
        let settings = makeRoutingSettings()
        for modifiers: NSEvent.ModifierFlags in [.shift, .option, .control, .command] {
            XCTAssertNil(ClipboardHistoryKeyAction.resolve(
                try keyEvent(kVK_Space, modifiers: modifiers), isEditingSearch: false, settings: settings
            ))
        }
    }

    func test_customPreviewShortcut_replacesSpaceAndStillRespectsDetailedSearch() throws {
        let settings = makeRoutingSettings()
        let combinations: [(Int, NSEvent.ModifierFlags)] = [
            (kVK_ANSI_P, [.command, .option]),
            (kVK_Space, [.control, .shift]),
        ]
        for (keyCode, modifiers) in combinations {
            settings.previewShortcut = FreePaste.KeyboardShortcut(keyCode: UInt16(keyCode), modifierFlags: modifiers)
            let event = try keyEvent(keyCode, modifiers: modifiers)

            XCTAssertEqual(ClipboardHistoryKeyAction.resolve(event, isEditingSearch: false, settings: settings), .preview)
            XCTAssertNil(ClipboardHistoryKeyAction.resolve(event, isEditingSearch: true, settings: settings))
            XCTAssertNil(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Space), isEditingSearch: false, settings: settings))
        }
        XCTAssertNil(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Space, modifiers: .control), isEditingSearch: false, settings: settings))
    }

    func test_previewShortcutRecorder_acceptsSpaceAndModifierCombinations() throws {
        let shortcuts: [(Int, NSEvent.ModifierFlags)] = [
            (kVK_Space, []), (kVK_ANSI_P, [.command, .option]), (kVK_Space, [.control, .shift]),
        ]
        for (keyCode, modifiers) in shortcuts {
            XCTAssertEqual(
                FreePaste.KeyboardShortcut.from(event: try keyEvent(keyCode, modifiers: modifiers)),
                FreePaste.KeyboardShortcut(keyCode: UInt16(keyCode), modifierFlags: modifiers)
            )
        }
    }

    func test_spacePreview_returnsAfterExitingDetailedSearch() throws {
        let settings = makeRoutingSettings()
        let space = try keyEvent(kVK_Space)
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.prepareForPresentation(itemIDs: [1, 2])
        navigation.beginEditingSearch()

        XCTAssertNil(ClipboardHistoryKeyAction.resolve(space, isEditingSearch: true, settings: settings))

        navigation.exitSearch(itemIDs: [1, 2])

        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(space, isEditingSearch: navigation.searchMode == .editing, settings: settings), .preview)
        XCTAssertEqual(navigation.selectedItemID, 1)
    }

    func test_detailedSearch_keepsAllListShortcutsWithNativeTextEditorUntilEscape() throws {
        let settings = makeRoutingSettings()
        let keys: [(Int, NSEvent.ModifierFlags)] = [
            (kVK_LeftArrow, []), (kVK_RightArrow, []), (kVK_UpArrow, []), (kVK_DownArrow, []),
            (kVK_ANSI_F, .control), (kVK_ANSI_B, .control), (kVK_Tab, []),
            (kVK_Return, []), (kVK_Return, .shift), (kVK_Delete, .command), (kVK_Space, []),
            (kVK_ANSI_D, .command), (kVK_ANSI_A, .command), (kVK_ANSI_C, .command),
            (kVK_ANSI_V, .command), (kVK_ANSI_Z, .command), (kVK_ANSI_F, .command),
        ]
        for (key, modifiers) in keys {
            XCTAssertNil(ClipboardHistoryKeyAction.resolve(try keyEvent(key, modifiers: modifiers), isEditingSearch: true, settings: settings))
        }
        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Escape), isEditingSearch: true, settings: settings), .exitEditing)
        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Escape), isEditingSearch: false, settings: settings), .closePanel)
    }

    func test_customizedNavigationSearchAndScopeShortcuts_obeyBothModes() throws {
        let settings = makeRoutingSettings()
        settings.nextItemShortcut = FreePaste.KeyboardShortcut(keyCode: UInt16(kVK_ANSI_N), modifierFlags: .control)
        settings.previousItemShortcut = FreePaste.KeyboardShortcut(keyCode: UInt16(kVK_ANSI_P), modifierFlags: .control)
        settings.focusSearchShortcut = FreePaste.KeyboardShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.command, .option])
        settings.switchPanelShortcut = FreePaste.KeyboardShortcut(keyCode: UInt16(kVK_Tab), modifierFlags: .option)
        let cases: [(Int, NSEvent.ModifierFlags, ClipboardHistoryKeyAction)] = [
            (kVK_ANSI_N, .control, .nextItem), (kVK_ANSI_P, .control, .previousItem),
            (kVK_ANSI_F, .command, .editSearch), (kVK_ANSI_S, [.command, .option], .editSearch),
            (kVK_Tab, [], .switchPanel), (kVK_Tab, .option, .switchPanel),
        ]
        for (key, modifiers, action) in cases {
            let event = try keyEvent(key, modifiers: modifiers)
            XCTAssertEqual(ClipboardHistoryKeyAction.resolve(event, isEditingSearch: false, settings: settings), action)
            XCTAssertNil(ClipboardHistoryKeyAction.resolve(event, isEditingSearch: true, settings: settings))
        }
    }

    func test_escapeAfterDetailedSearch_immediatelyRestoresSelectionAndPasteActions() throws {
        let settings = makeRoutingSettings()
        var navigation = ClipboardHistoryNavigation<Int>()
        navigation.prepareForPresentation(itemIDs: [1, 2, 3])
        navigation.beginEditingSearch()
        let right = try keyEvent(kVK_RightArrow)
        XCTAssertNil(ClipboardHistoryKeyAction.resolve(right, isEditingSearch: navigation.searchMode == .editing, settings: settings))
        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(try keyEvent(kVK_Escape), isEditingSearch: true, settings: settings), .exitEditing)

        navigation.exitSearch(itemIDs: [1, 2, 3])

        XCTAssertEqual(ClipboardHistoryKeyAction.resolve(right, isEditingSearch: navigation.searchMode == .editing, settings: settings), .nextItem)
        XCTAssertTrue(navigation.move(step: 1, itemIDs: [1, 2, 3]))
        XCTAssertEqual(navigation.confirmedItemID(in: [1, 2, 3]), 2)
    }

    func test_nativeFieldEditorComposition_doesNotReachPanelUntilCommitted() {
        let editor = NSTextView(frame: .zero)
        editor.isFieldEditor = true
        editor.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(KeyboardEventMonitor.shouldRouteToPanel(
            isFieldEditor: editor.isFieldEditor, keyCode: UInt16(kVK_Return),
            handlesFieldEditorEvents: true, hasMarkedText: editor.hasMarkedText()
        ))
        editor.insertText("中文", replacementRange: editor.markedRange())
        editor.unmarkText()
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertTrue(KeyboardEventMonitor.shouldRouteToPanel(
            isFieldEditor: editor.isFieldEditor, keyCode: UInt16(kVK_Return),
            handlesFieldEditorEvents: true, hasMarkedText: editor.hasMarkedText()
        ))
    }

    private func keyEvent(_ keyCode: Int, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(keyCode)
        ))
    }

    func test_searchCaret_followsQuickEditingEscapeAndFavoritesTransitions() async {
        await MainActor.run {
            let editor = NSTextView(frame: .zero)
            editor.isFieldEditor = true
            editor.insertionPointColor = .systemRed
            let controller = FieldEditorInsertionPointController()
            var navigation = ClipboardHistoryNavigation<Int>()
            navigation.prepareForPresentation(itemIDs: [1, 2])

            controller.update(editor: editor, isHidden: navigation.searchMode == .quick)
            XCTAssertEqual(editor.insertionPointColor, .clear)

            navigation.beginEditingSearch()
            controller.update(editor: editor, isHidden: navigation.searchMode == .quick)
            XCTAssertEqual(editor.insertionPointColor, .systemRed)

            navigation.exitSearch(itemIDs: [1, 2])
            _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [3])
            controller.update(editor: editor, isHidden: navigation.searchMode == .quick)
            XCTAssertEqual(editor.insertionPointColor, .clear)

            controller.restore()
            XCTAssertEqual(editor.insertionPointColor, .systemRed)
        }
    }

    func test_searchCaret_repeatedUpdatesPreserveOriginalColor() async {
        await MainActor.run {
            let editor = NSTextView(frame: .zero)
            editor.isFieldEditor = true
            editor.insertionPointColor = .systemGreen
            let controller = FieldEditorInsertionPointController()

            controller.update(editor: editor, isHidden: true)
            controller.update(editor: editor, isHidden: true)
            controller.update(editor: editor, isHidden: false)

            XCTAssertEqual(editor.insertionPointColor, .systemGreen)
        }
    }

    func test_searchCaret_restoresPreviousEditorWhenFocusChangesOrEnds() async {
        await MainActor.run {
            let first = NSTextView(frame: .zero)
            first.isFieldEditor = true
            first.insertionPointColor = .systemRed
            let second = NSTextView(frame: .zero)
            second.isFieldEditor = true
            second.insertionPointColor = .systemBlue
            let controller = FieldEditorInsertionPointController()

            controller.update(editor: first, isHidden: true)
            controller.update(editor: second, isHidden: true)
            XCTAssertEqual(first.insertionPointColor, .systemRed)
            XCTAssertEqual(second.insertionPointColor, .clear)

            controller.update(editor: nil, isHidden: true)
            XCTAssertEqual(second.insertionPointColor, .systemBlue)
        }
    }

    func test_searchCaret_doesNotChangeNonFieldEditors() async {
        await MainActor.run {
            let editor = NSTextView(frame: .zero)
            editor.insertionPointColor = .systemRed
            let controller = FieldEditorInsertionPointController()

            controller.update(editor: editor, isHidden: true)

            XCTAssertEqual(editor.insertionPointColor, .systemRed)
        }
    }

    func test_searchCaretCoordinator_keepsNativeFocusAndRestoresOnStop() async {
        await MainActor.run {
            let window = SearchCaretTestWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
            window.contentView = root
            let catcher = KeyboardEventMonitor.FocusCatcherView(frame: .zero)
            root.addSubview(catcher)
            let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
            editor.isFieldEditor = true
            editor.insertionPointColor = .systemRed
            root.addSubview(editor)
            XCTAssertTrue(window.makeFirstResponder(editor))

            let coordinator = KeyboardEventMonitor.Coordinator(onKeyDown: { _ in false })
            coordinator.attach(to: catcher)
            coordinator.update(
                onKeyDown: { _ in false }, focusRequestID: 0,
                handlesFieldEditorEvents: true, hidesFieldEditorInsertionPoint: true
            )
            coordinator.start()
            defer { coordinator.stop() }
            XCTAssertEqual(editor.insertionPointColor, .clear)
            XCTAssertTrue(window.firstResponder === editor)

            coordinator.update(
                onKeyDown: { _ in false }, focusRequestID: 0,
                handlesFieldEditorEvents: true, hidesFieldEditorInsertionPoint: false
            )
            XCTAssertEqual(editor.insertionPointColor, .systemRed)
            XCTAssertTrue(window.firstResponder === editor)

            coordinator.update(
                onKeyDown: { _ in false }, focusRequestID: 0,
                handlesFieldEditorEvents: true, hidesFieldEditorInsertionPoint: true
            )
            coordinator.stop()
            XCTAssertEqual(editor.insertionPointColor, .systemRed)
            coordinator.update(
                onKeyDown: { _ in false }, focusRequestID: 0,
                handlesFieldEditorEvents: true, hidesFieldEditorInsertionPoint: true
            )
            XCTAssertEqual(editor.insertionPointColor, .systemRed)
        }
    }

    func test_searchCaret_preservesNativeTextSelectionAndComposition() async {
        await MainActor.run {
            let editor = NSTextView(frame: .zero)
            editor.isFieldEditor = true
            editor.string = "email"
            editor.setSelectedRange(NSRange(location: 5, length: 0))
            let controller = FieldEditorInsertionPointController()

            controller.update(editor: editor, isHidden: true)
            XCTAssertEqual(editor.string, "email")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0))

            editor.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            controller.update(editor: editor, isHidden: true)
            XCTAssertTrue(editor.hasMarkedText())
            editor.insertText("中文", replacementRange: editor.markedRange())
            editor.unmarkText()
            XCTAssertEqual(editor.string, "email中文")
            XCTAssertEqual(editor.insertionPointColor, .clear)
            controller.restore()
        }
    }

    private func makeRoutingSettings() -> FreePaste.AppSettings {
        let suiteName = "ClipboardHistoryKeyActionTests.\(UUID().uuidString)"
        routingDefaultsSuiteNames.append(suiteName)
        return FreePaste.AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    func test_switchPanel_restoresSavedSelectionWhenStillPresent() {
        var navigation = ClipboardHistoryNavigation<Int>()
        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])
        navigation.select(20)
        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])

        // Switch back to favorites — 20 should be restored
        _ = navigation.switchPanel(recentIDs: [1, 2], favoriteIDs: [10, 20])

        XCTAssertEqual(navigation.selectedItemID, 20)
    }
}

private final class SearchCaretTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
