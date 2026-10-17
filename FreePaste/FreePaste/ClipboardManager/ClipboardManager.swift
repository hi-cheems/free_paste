//
//  ClipboardManager.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/13.
//

import AppKit
import Combine
import Foundation

/// 提供当前前台应用的 bundle ID，用于黑名单过滤。独立于 DirectPasteService 以避免跨编译单元依赖。
protocol ClipboardSourceProviding {
    var currentSourceBundleID: String? { get }
}

struct WorkspaceClipboardSourceProvider: ClipboardSourceProviding {
    var currentSourceBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

/// 剪切板管理器：连接 Monitor（监听）与 Store（存储），提供对外统一接口
///
/// 作为整个 App 的核心协调层，职责包括：
/// - 监听剪切板变化并自动保存
/// - 暴露 `@Published items` 供 UI 绑定
/// - 管理用户设置（最大条目数、去重开关）
///
/// 使用示例：
/// ```swift
/// let manager = ClipboardManager()
/// manager.start()
/// // SwiftUI 中：
/// ForEach(manager.items) { item in ... }
/// ```
final class ClipboardManager: ObservableObject {

    // MARK: - 对外状态

    /// 当前历史记录列表（按时间倒序），UI 可直接绑定
    @Published private(set) var items: [ClipboardItem] = []
    /// 未收藏的历史记录
    @Published private(set) var unpinnedItems: [ClipboardItem] = []
    /// 收藏的历史记录
    @Published private(set) var pinnedItems: [ClipboardItem] = []
    /// Emits each supported clipboard change after blacklist filtering, before history pause/deduplication.
    let capturedItem = PassthroughSubject<ClipboardItem, Never>()

    // MARK: - 依赖

    private let monitor: ClipboardMonitor
    private let store: ClipboardHistoryStore
    private let settings: AppSettings
    private let clipboardSourceProvider: any ClipboardSourceProviding
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    /// - Parameters:
    ///   - monitor: 剪切板监听器
    ///   - store: 历史记录存储
    init(
        monitor: ClipboardMonitor,
        store: ClipboardHistoryStore,
        settings: AppSettings,
        clipboardSourceProvider: any ClipboardSourceProviding = WorkspaceClipboardSourceProvider()
    ) {
        self.monitor = monitor
        self.store = store
        self.settings = settings
        self.clipboardSourceProvider = clipboardSourceProvider
        _ = pruneStore()
        reloadItems()
        bindSettings()
        bindMonitor()
        prepareLegacyMetadata()
    }

    /// 便捷初始化，使用默认的系统剪切板监听器和持久化存储
    convenience init() {
        self.init(
            monitor: ClipboardMonitor(),
            store: ClipboardHistoryStore(),
            settings: AppSettings()
        )
    }

    // MARK: - 生命周期

    /// 开始监听剪切板
    func start() {
        monitor.start()
    }

    /// 停止监听剪切板
    func stop() {
        monitor.stop()
    }

    /// Returns the current supported clipboard payload for the first batch item.
    /// A pending monitor tick is consumed here so it cannot append the same payload twice.
    func currentItemForBatchPaste() -> ClipboardItem? {
        let item = monitor.currentItem()
        let hadUnobservedChange = monitor.syncChangeCount()
        guard !isCurrentSourceBlocked(), let item else { return nil }
        if hadUnobservedChange {
            recordInHistoryIfEnabled(item)
        }
        return item
    }

    // MARK: - 操作

    /// 删除指定条目
    func delete(_ item: ClipboardItem) {
        let removedIDs = store.delete(id: item.id)
        removePublishedItems(withIDs: removedIDs)
    }

    /// 清空全部未收藏的历史记录
    func deleteAll() {
        let removedIDs = store.deleteAll()
        removePublishedItems(withIDs: removedIDs)
    }

    /// 收藏指定条目
    @discardableResult
    func pin(_ item: ClipboardItem, key: String) -> Bool {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, store.pin(id: item.id, key: normalizedKey) else { return false }
        updatePublishedPinState(id: item.id, isPinned: true, favoriteKey: normalizedKey)
        return true
    }

    /// 取消收藏指定条目
    func unpin(_ item: ClipboardItem) {
        guard store.unpin(id: item.id) else { return }
        updatePublishedPinState(id: item.id, isPinned: false)
    }

    @discardableResult
    func updateFavoriteKey(_ item: ClipboardItem, key: String) -> Bool {
        guard store.updateFavoriteKey(id: item.id, key: key) else { return false }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        updatePublishedPinState(
            id: item.id, isPinned: true, favoriteKey: normalizedKey.isEmpty ? nil : normalizedKey
        )
        return true
    }

    /// 按关键词搜索未收藏记录
    func searchUnpinned(query: String) -> [ClipboardItem] {
        store.searchUnpinned(query: query)
    }

    /// 按关键词搜索收藏记录
    func searchPinned(query: String) -> [ClipboardItem] {
        store.searchPinned(query: query)
    }

    /// 按关键词搜索全部记录
    func search(query: String) -> [ClipboardItem] {
        store.search(query: query)
    }

    /// 将文本条目以纯文本格式写入剪切板（只写 .string 类型，剥去富文本）。
    /// 非文本条目返回 false，不修改剪切板。
    @discardableResult
    func copyToPasteboardAsPlainText(_ item: ClipboardItem) -> Bool {
        guard case .text(let text) = item.content else { return false }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        monitor.syncChangeCount()
        #endif
        return true
    }

    /// 将指定条目的内容写回系统剪切板（重新复制）
    func copyToPasteboard(_ item: ClipboardItem) {
        #if canImport(AppKit)
        let item = materializedItem(for: item)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            if let richData = item.richData, !richData.isEmpty {
                for (typeRaw, data) in richData {
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
                }
            }
            pasteboard.setString(text, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .tiff)
        case .fileURLs(let urls):
            pasteboard.writeObjects(urls as [NSURL])
        }
        monitor.syncChangeCount()
        #endif
    }

    /// Resolves a lightweight history summary only when an operation needs the original payload.
    func materializedItem(for item: ClipboardItem) -> ClipboardItem {
        guard item.payloadAvailability == .summary else { return item }
        return store.fetch(id: item.id) ?? item
    }

    // MARK: - Private

    private func bindMonitor() {
        monitor.newItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.handleNewItem(item)
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        // 当影响裁剪的设置变更时，重新裁剪历史记录。
        // 必须用 receive(on: DispatchQueue.main)：@Published 在 willSet 触发，此时属性尚未更新；
        // 通过 main queue async 调度，确保 didSet 执行完毕后再读取新值。
        let pruningPublisher = Publishers.Merge3(
            settings.$maxItems.dropFirst().removeDuplicates().map { _ in () },
            settings.$maxTotalSizeMB.dropFirst().removeDuplicates().map { _ in () },
            settings.$retentionDays.dropFirst().removeDuplicates().map { _ in () }
        )
        pruningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.pruneHistory() }
            .store(in: &cancellables)
    }

    private func handleNewItem(_ item: ClipboardItem) {
        guard !isCurrentSourceBlocked() else { return }
        capturedItem.send(item)
        recordInHistoryIfEnabled(item)
    }

    private func isCurrentSourceBlocked() -> Bool {
        guard let bundleID = clipboardSourceProvider.currentSourceBundleID else { return false }
        return settings.blockedBundleIDs.contains(bundleID)
    }

    private func recordInHistoryIfEnabled(_ item: ClipboardItem) {
        guard settings.effectiveRecordingPauseState == .active else { return }
        let mutation = store.add(item, deduplicate: settings.deduplicateEnabled)
        let prunedIDs = pruneStore()
        applyHistoryMutation(
            mutation,
            additionallyRemoving: prunedIDs
        )
    }

    private func reloadItems() {
        let snapshot = store.fetchSnapshot()
        items = snapshot.items
        unpinnedItems = snapshot.unpinnedItems
        pinnedItems = snapshot.pinnedItems
    }

    private func pruneHistory() {
        removePublishedItems(withIDs: pruneStore())
    }

    private func pruneStore() -> Set<ClipboardItem.ID> {
        let expirationDate = settings.retentionDays > 0
            ? Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: Date())
            : nil
        let maxTotalBytes = settings.maxTotalSizeMB > 0 ? settings.maxTotalSizeMB * 1_048_576 : 0

        return store.pruneHistory(
            maxCount: settings.maxItems,
            maxTotalTextBytes: maxTotalBytes,
            removingItemsOlderThan: expirationDate
        )
    }

    private func prepareLegacyMetadata() {
        store.prepareLegacyMetadataBatch { [weak self] processedEntries, summariesChanged, mayHaveMore in
            guard let self else { return }
            if mayHaveMore {
                if summariesChanged {
                    self.reloadItems()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.prepareLegacyMetadata()
                }
            } else if processedEntries {
                let removedIDs = self.pruneStore()
                if summariesChanged {
                    self.reloadItems()
                } else {
                    self.removePublishedItems(withIDs: removedIDs)
                }
            }
        }
    }

    private func applyHistoryMutation(
        _ mutation: ClipboardHistoryMutation,
        additionallyRemoving additionalRemovedIDs: Set<ClipboardItem.ID>
    ) {
        let removedIDs = mutation.removedItemIDs.union(additionalRemovedIDs)
        var updatedItems = items.filter { !removedIDs.contains($0.id) }

        if let insertedItem = mutation.insertedItem {
            updatedItems.removeAll { $0.id == insertedItem.id }
            let insertionIndex = updatedItems.firstIndex {
                $0.timestamp < insertedItem.timestamp
            } ?? updatedItems.endIndex
            updatedItems.insert(insertedItem, at: insertionIndex)
        }
        publish(items: updatedItems)
    }

    private func removePublishedItems(withIDs removedIDs: Set<ClipboardItem.ID>) {
        guard !removedIDs.isEmpty else { return }
        publish(items: items.filter { !removedIDs.contains($0.id) })
    }

    private func updatePublishedPinState(id: ClipboardItem.ID, isPinned: Bool, favoriteKey: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updatedItems = items
        updatedItems[index].isPinned = isPinned
        updatedItems[index].favoriteKey = favoriteKey
        publish(items: updatedItems)
    }

    private func publish(items updatedItems: [ClipboardItem]) {
        items = updatedItems
        unpinnedItems = updatedItems.filter { !$0.isPinned }
        pinnedItems = updatedItems.filter(\.isPinned)
    }
}
