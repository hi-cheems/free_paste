//
//  ClipboardHistoryNavigation.swift
//  FreePaste
//
//  Created by Codex on 2026/3/15.
//

import Foundation

/// Pure navigation state for the history panel so keyboard behavior stays testable outside SwiftUI.
struct ClipboardHistoryNavigation<ItemID: Hashable> {
    enum SearchMode {
        case quick
        case editing
    }

    enum Panel {
        case recent
        case favorites
    }

    private(set) var selectedItemID: ItemID?
    private(set) var searchMode: SearchMode = .quick
    private(set) var activePanel: Panel = .recent

    // Per-panel selection memory
    private var recentSelectedID: ItemID?
    private var favoritesSelectedID: ItemID?

    mutating func resetSelection(itemIDs: [ItemID]) {
        // Preserve the current selection when it still exists after filtering or deletion.
        if let selectedItemID, itemIDs.contains(selectedItemID) {
            return
        }
        selectedItemID = itemIDs.first
        saveSelectionForCurrentPanel()
    }

    mutating func prepareForPresentation(itemIDs: [ItemID]) {
        resetSelection(itemIDs: itemIDs)
        searchMode = .quick
    }

    func shouldHandlePanelKeyEvent() -> Bool {
        searchMode == .quick
    }

    /// Unconditionally select the first item. Used when new items arrive at the top.
    mutating func selectFirst(itemIDs: [ItemID]) {
        selectedItemID = itemIDs.first
        saveSelectionForCurrentPanel()
    }

    mutating func beginEditingSearch() {
        searchMode = .editing
    }

    mutating func exitSearch(itemIDs: [ItemID]) {
        resetSelection(itemIDs: itemIDs)
        searchMode = .quick
    }

    mutating func select(_ itemID: ItemID) {
        selectedItemID = itemID
        saveSelectionForCurrentPanel()
    }

    /// Switch between recent and favorites panels.
    /// Returns the new active panel.
    mutating func switchPanel(recentIDs: [ItemID], favoriteIDs: [ItemID]) -> Panel {
        // Save current selection
        saveSelectionForCurrentPanel()

        // Toggle
        activePanel = activePanel == .recent ? .favorites : .recent

        // Restore selection for the target panel
        let targetIDs = activePanel == .recent ? recentIDs : favoriteIDs
        let savedID = activePanel == .recent ? recentSelectedID : favoritesSelectedID

        if let savedID, targetIDs.contains(savedID) {
            selectedItemID = savedID
        } else {
            selectedItemID = targetIDs.first
        }
        saveSelectionForCurrentPanel()

        return activePanel
    }

    mutating func move(step: Int, itemIDs: [ItemID]) -> Bool {
        guard searchMode == .quick, !itemIDs.isEmpty else { return false }

        guard let currentIndex = selectedIndex(in: itemIDs) else {
            selectedItemID = itemIDs.first
            saveSelectionForCurrentPanel()
            return true
        }

        let nextIndex = max(0, min(itemIDs.count - 1, currentIndex + step))
        selectedItemID = itemIDs[nextIndex]
        saveSelectionForCurrentPanel()
        return true
    }

    func confirmedItemID(in itemIDs: [ItemID]) -> ItemID? {
        guard searchMode == .quick else { return nil }
        guard let selectedItemID else { return nil }
        // Search filtering can invalidate the old selection, so confirm only visible items.
        return itemIDs.contains(selectedItemID) ? selectedItemID : nil
    }

    mutating func deleteSelectedItem(in itemIDs: [ItemID]) -> ItemID? {
        guard
            searchMode == .quick,
            let currentIndex = selectedIndex(in: itemIDs)
        else { return nil }

        let deletedItemID = itemIDs[currentIndex]
        var remainingItemIDs = itemIDs
        remainingItemIDs.remove(at: currentIndex)

        if remainingItemIDs.isEmpty {
            selectedItemID = nil
            saveSelectionForCurrentPanel()
            return deletedItemID
        }

        let fallbackIndex = min(currentIndex, remainingItemIDs.count - 1)
        selectedItemID = remainingItemIDs[fallbackIndex]
        saveSelectionForCurrentPanel()
        return deletedItemID
    }

    private func selectedIndex(in itemIDs: [ItemID]) -> Int? {
        guard let selectedItemID else { return nil }
        return itemIDs.firstIndex(of: selectedItemID)
    }

    private mutating func saveSelectionForCurrentPanel() {
        switch activePanel {
        case .recent:
            recentSelectedID = selectedItemID
        case .favorites:
            favoritesSelectedID = selectedItemID
        }
    }
}
