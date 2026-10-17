//
//  ClipboardHistoryView.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/13.
//

import Carbon.HIToolbox
import SwiftUI

enum ClipboardHistoryPanelLayout {
    static let heightRatio: CGFloat = 0.2
    static let minimumHeight: CGFloat = 180
    static let maximumHeight: CGFloat = 260

    static func frame(in visibleFrame: CGRect) -> CGRect {
        let preferredHeight = visibleFrame.height * heightRatio
        let height = min(visibleFrame.height, min(maximumHeight, max(minimumHeight, preferredHeight)))
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: height
        )
    }
}

enum ClipboardHistorySelectionScrollBehavior {
    static let anchor: UnitPoint? = nil
}

struct ClipboardHistoryView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var uiState: AppUIState
    let onConfirm: (ClipboardItem) -> Void
    let onOpenSettings: () -> Void
    let onPreview: (ClipboardItem) -> Void
    let onClosePreview: () -> Void
    let onPlainTextConfirm: (ClipboardItem) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var navigation = ClipboardHistoryNavigation<ClipboardItem.ID>()
    @State private var displayedItems: [ClipboardItem] = []
    @State private var showClearConfirmation = false
    @State private var favoriteKeyEditorItem: ClipboardItem?
    @State private var restoreEditingSearchAfterKeyEditor = false
    @FocusState private var isSearchFocused: Bool

    init(
        onConfirm: @escaping (ClipboardItem) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {},
        onPreview: @escaping (ClipboardItem) -> Void = { _ in },
        onClosePreview: @escaping () -> Void = {},
        onPlainTextConfirm: @escaping (ClipboardItem) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.onConfirm = onConfirm
        self.onOpenSettings = onOpenSettings
        self.onPreview = onPreview
        self.onClosePreview = onClosePreview
        self.onPlainTextConfirm = onPlainTextConfirm
        self.onCancel = onCancel
    }

    private var isRecent: Bool {
        navigation.activePanel == .recent
    }

    private func computeDisplayedItems() -> [ClipboardItem] {
        if isRecent {
            return searchText.isEmpty ? manager.items : manager.search(query: searchText)
        }
        return searchText.isEmpty ? manager.pinnedItems : manager.searchPinned(query: searchText)
    }

    private var currentPanelSourceIDs: [ClipboardItem.ID] {
        (isRecent ? manager.items : manager.pinnedItems).map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            itemStrip
        }
        .background(AppTheme.surfaceMuted)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.panelStroke.opacity(0.72))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background(
            KeyboardEventMonitor(
                handlesFieldEditorEvents: true,
                hidesFieldEditorInsertionPoint: navigation.searchMode == .quick,
                onKeyDown: handleKeyDown
            )
        )
        .tint(AppTheme.accent)
        .preferredColorScheme(.light)
        .onAppear {
            displayedItems = computeDisplayedItems()
            prepareForPresentation()
        }
        .onChange(of: uiState.historyPopoverPresentationID) { _, _ in
            displayedItems = computeDisplayedItems()
            prepareForPresentation()
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused, uiState.isHistoryPopoverVisible,
               favoriteKeyEditorItem == nil, !showClearConfirmation {
                DispatchQueue.main.async { requestSearchFocus() }
            }
        }
        .onChange(of: showClearConfirmation) { _, shown in
            if !shown { requestSearchFocus() }
        }
        .onChange(of: searchText) { _, _ in
            displayedItems = computeDisplayedItems()
            navigation.selectFirst(itemIDs: displayedItems.map(\.id))
            onClosePreview()
        }
        .onChange(of: currentPanelSourceIDs) { oldIDs, newIDs in
            displayedItems = computeDisplayedItems()
            if isRecent, let first = newIDs.first, !oldIDs.contains(first) {
                navigation.selectFirst(itemIDs: displayedItems.map(\.id))
            } else {
                resetSelection()
            }
        }
        .alert("清空未收藏记录？", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                manager.deleteAll()
            }
        } message: {
            Text("收藏内容会保留。")
        }
        .sheet(item: $favoriteKeyEditorItem, onDismiss: restoreFocusAfterKeyEditor) { item in
            FavoriteKeyEditorView(
                item: item,
                onSave: { key in saveFavoriteKey(for: item, key: key) },
                onCancel: { favoriteKeyEditorItem = nil }
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            panelSwitcher

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(navigation.searchMode == .editing ? AppTheme.accent : AppTheme.textMuted)

                TextField(isRecent ? "搜索记录" : "搜索 Key 或内容", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .font(.system(size: 13, weight: .medium))
                    .simultaneousGesture(TapGesture().onEnded {
                        navigation.beginEditingSearch()
                        onClosePreview()
                    })

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textMuted)
                    .help("清空搜索")
                }

                if navigation.searchMode == .quick {
                    Text("⌘F 编辑")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textMuted)
                        .fixedSize()
                        .help("按 Command + F 详细编辑搜索内容")
                        .accessibilityLabel("按 Command F 详细编辑搜索内容")
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 300, height: 32)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(navigation.searchMode == .editing ? AppTheme.accent.opacity(0.65) : AppTheme.line, lineWidth: 1)
            )

            Text(resultCountText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(AppTheme.surfaceSubtle)
                .clipShape(Capsule())

            toolbarStatus

            Spacer(minLength: 12)

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PanelIconButtonStyle())
            .help("打开设置")

            if isRecent && !manager.unpinnedItems.isEmpty {
                Button {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(PanelIconButtonStyle(foreground: AppTheme.danger))
                .help("清空未收藏记录")
            }

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PanelIconButtonStyle())
            .help("关闭")
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.lineSoft)
                .frame(height: 1)
        }
    }

    private var panelSwitcher: some View {
        HStack(spacing: 2) {
            panelButton(
                title: "最近",
                iconName: "clock.arrow.circlepath",
                panel: .recent,
                count: manager.items.count
            )
            panelButton(
                title: "收藏",
                iconName: "star.fill",
                panel: .favorites,
                count: manager.pinnedItems.count
            )
        }
        .padding(2)
        .background(AppTheme.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("按 \(settings.switchPanelShortcut.displayText) 切换")
    }

    private func panelButton(
        title: String,
        iconName: String,
        panel: ClipboardHistoryNavigation<ClipboardItem.ID>.Panel,
        count: Int
    ) -> some View {
        let isActive = navigation.activePanel == panel
        return Button {
            activatePanel(panel)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                if panel == .favorites, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textMuted)
                }
            }
            .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(isActive ? AppTheme.surfaceElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var toolbarStatus: some View {
        if let inlineMessage = uiState.inlineMessage {
            compactToolbarStatus(
                iconName: inlineMessage.iconName,
                text: inlineMessage.text,
                tone: inlineMessage.tone == .warning ? AppTheme.warning : AppTheme.accent,
                actionTitle: inlineMessage.action?.title,
                action: inlineMessage.action.map { action in { action.perform() } }
            )
        } else if let pauseStatusText = settings.recordingPauseStatusText {
            compactToolbarStatus(
                iconName: "pause.circle.fill",
                text: pauseStatusText,
                tone: AppTheme.warning,
                actionTitle: "恢复",
                action: { settings.resumeRecording() }
            )
        }
    }

    private func compactToolbarStatus(
        iconName: String,
        text: String,
        tone: Color,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tone)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(tone.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(tone.opacity(0.16), lineWidth: 1)
        }
    }

    private var itemStrip: some View {
        Group {
            if displayedItems.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    let verticalInset: CGFloat = 8
                    let cardHeight = max(96, geometry.size.height - verticalInset * 2)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(displayedItems) { item in
                                    ClipboardItemRow(
                                        item: item,
                                        isSelected: item.id == navigation.selectedItemID && navigation.searchMode == .quick,
                                        cardHeight: cardHeight,
                                        onSelect: {
                                            navigation.select(item.id)
                                            requestSearchFocus()
                                        },
                                        onConfirm: {
                                            confirmSelection(item)
                                        },
                                        onTogglePin: {
                                            togglePin(item)
                                        },
                                        onPlainTextPaste: {
                                            confirmPlainTextSelection(item)
                                        },
                                        onEditFavoriteKey: {
                                            presentFavoriteKeyEditor(for: item)
                                        },
                                        onPreview: {
                                            navigation.select(item.id)
                                            onPreview(item)
                                        }
                                    )
                                    .environmentObject(manager)
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, verticalInset)
                        }
                        .onChange(of: navigation.selectedItemID) { _, itemID in
                            guard let itemID else { return }
                            withAnimation(.easeOut(duration: 0.14)) {
                                proxy.scrollTo(
                                    itemID,
                                    anchor: ClipboardHistorySelectionScrollBehavior.anchor
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surfaceMuted)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppTheme.textMuted)
            VStack(alignment: .leading, spacing: 3) {
                Text(emptyStateTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(emptyStateMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultCountText: String {
        if !searchText.isEmpty {
            return "找到 \(displayedItems.count) 条"
        }
        return isRecent ? "\(displayedItems.count) 条" : "\(displayedItems.count) 条收藏"
    }

    private var emptyStateIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return isRecent ? "doc.on.clipboard" : "star"
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty { return "没有匹配的记录" }
        return isRecent ? "暂无剪贴板记录" : "暂无收藏"
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty { return "换个关键词试试。" }
        return isRecent ? "复制内容后会显示在这里。" : "在最近记录中点按星标即可收藏。"
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard favoriteKeyEditorItem == nil else { return false }
        switch ClipboardHistoryKeyAction.resolve(
            event, isEditingSearch: !navigation.shouldHandlePanelKeyEvent(), settings: settings
        ) {
        case .closePanel:
            onCancel()
            return true
        case .exitEditing:
            return handleExitSearch()
        case .editSearch:
            return handleFocusSearch()
        case .switchPanel:
            return handleSwitchPanel()
        case .togglePin:
            return handleTogglePin()
        case .nextItem:
            return handleMove(step: 1)
        case .previousItem:
            return handleMove(step: -1)
        case .deleteItem:
            return handleDeleteSelection()
        case .pastePlainText:
            return handlePlainTextConfirm()
        case .paste:
            return handleConfirm()
        case nil:
            return false
        }
    }

    private func handleSwitchPanel() -> Bool {
        performSwitchPanel()
        return true
    }

    private func activatePanel(_ panel: ClipboardHistoryNavigation<ClipboardItem.ID>.Panel) {
        guard navigation.activePanel != panel else { return }
        performSwitchPanel()
    }

    private func performSwitchPanel() {
        let recentItems = searchText.isEmpty ? manager.items : manager.search(query: searchText)
        let favoriteItems = searchText.isEmpty ? manager.pinnedItems : manager.searchPinned(query: searchText)
        _ = navigation.switchPanel(
            recentIDs: recentItems.map(\.id),
            favoriteIDs: favoriteItems.map(\.id)
        )
        displayedItems = computeDisplayedItems()
        onClosePreview()

        requestSearchFocus()
    }

    private func handleTogglePin() -> Bool {
        guard
            navigation.searchMode == .quick,
            let selectedID = navigation.selectedItemID,
            let item = displayedItems.first(where: { $0.id == selectedID })
        else { return false }
        togglePin(item)
        return true
    }

    private func togglePin(_ item: ClipboardItem) {
        if item.isPinned {
            if !isRecent, navigation.selectedItemID == item.id {
                _ = navigation.deleteSelectedItem(in: displayedItems.map(\.id))
            }
            manager.unpin(item)
            displayedItems = computeDisplayedItems()
            resetSelection()
            restoreFocusAfterKeyEditor()
        } else {
            presentFavoriteKeyEditor(for: item)
        }
    }

    private func presentFavoriteKeyEditor(for item: ClipboardItem) {
        restoreEditingSearchAfterKeyEditor = navigation.searchMode == .editing
        onClosePreview()
        favoriteKeyEditorItem = item
    }

    private func saveFavoriteKey(for item: ClipboardItem, key: String) -> Bool {
        let saved = item.isPinned
            ? manager.updateFavoriteKey(item, key: key)
            : manager.pin(item, key: key)
        guard saved else { return false }
        displayedItems = computeDisplayedItems()
        resetSelection()
        favoriteKeyEditorItem = nil
        return true
    }

    private func restoreFocusAfterKeyEditor() {
        if restoreEditingSearchAfterKeyEditor {
            navigation.beginEditingSearch()
        }
        restoreEditingSearchAfterKeyEditor = false
        requestSearchFocus()
    }

    private func handleFocusSearch() -> Bool {
        focusSearchField()
        return true
    }

    private func handleExitSearch() -> Bool {
        navigation.exitSearch(itemIDs: displayedItems.map(\.id))
        requestSearchFocus()
        return true
    }

    private func handleMove(step: Int) -> Bool {
        let handled = navigation.move(step: step, itemIDs: displayedItems.map(\.id))
        if handled {
            requestSearchFocus()
        }
        return handled
    }

    private func handleConfirm() -> Bool {
        guard
            let selectedID = navigation.confirmedItemID(in: displayedItems.map(\.id)),
            let item = displayedItems.first(where: { $0.id == selectedID })
        else { return false }
        confirmSelection(item)
        return true
    }

    private func handleDeleteSelection() -> Bool {
        guard
            navigation.searchMode == .quick,
            let selectedID = navigation.deleteSelectedItem(in: displayedItems.map(\.id)),
            let item = displayedItems.first(where: { $0.id == selectedID })
        else { return false }

        manager.delete(item)
        displayedItems = computeDisplayedItems()
        requestSearchFocus()
        return true
    }

    private func handlePlainTextConfirm() -> Bool {
        guard
            let selectedID = navigation.confirmedItemID(in: displayedItems.map(\.id)),
            let item = displayedItems.first(where: { $0.id == selectedID }),
            case .text = item.content
        else { return false }
        confirmPlainTextSelection(item)
        return true
    }

    private func confirmPlainTextSelection(_ item: ClipboardItem) {
        navigation.select(item.id)
        onClosePreview()
        onPlainTextConfirm(item)
    }

    private func confirmSelection(_ item: ClipboardItem) {
        navigation.select(item.id)
        onClosePreview()
        onConfirm(item)
    }

    private func resetSelection() {
        navigation.resetSelection(itemIDs: displayedItems.map(\.id))
    }

    private func focusSearchField() {
        navigation.beginEditingSearch()
        requestSearchFocus(selectAll: true)
        onClosePreview()
    }

    private func prepareForPresentation() {
        navigation.prepareForPresentation(itemIDs: displayedItems.map(\.id))
        requestSearchFocus(selectAll: true)
        onClosePreview()
    }

    private func requestSearchFocus(selectAll: Bool = false) {
        guard uiState.isHistoryPopoverVisible, favoriteKeyEditorItem == nil, !showClearConfirmation else { return }
        if selectAll && isSearchFocused {
            isSearchFocused = false
            DispatchQueue.main.async {
                requestSearchFocus()
            }
        } else {
            isSearchFocused = true
        }
    }
}

private struct PanelIconButtonStyle: ButtonStyle {
    var foreground: Color = AppTheme.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? AppTheme.surfaceSubtle : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppTheme.lineSoft, lineWidth: 1)
            )
    }
}
