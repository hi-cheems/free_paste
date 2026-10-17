//
//  ClipboardManagerTests.swift
//  FreePasteTests
//
//  Created by bond cheems on 2026/3/13.
//

import Combine
import XCTest

@testable import FreePaste

final class ClipboardManagerTests: XCTestCase {

    private var manager: ClipboardManager!
    private var monitor: ClipboardMonitor!
    private var pasteboard: MockPasteboard!
    private var store: ClipboardHistoryStore!
    private var settings: AppSettings!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        pasteboard = MockPasteboard()
        monitor = ClipboardMonitor(pasteboard: pasteboard, interval: 0.05)
        store = ClipboardHistoryStore(inMemory: true)
        defaultsSuiteName = "ClipboardManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        settings = AppSettings(defaults: defaults)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)
        cancellables = []
    }

    override func tearDown() {
        manager.stop()
        cancellables = nil
        manager = nil
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - 自动保存

    func test_whenClipboardChanges_itemIsSavedAndPublished() {
        let expectation = expectation(description: "items 被更新")
        let initialSnapshotFetchCount = store.snapshotFetchCount

        manager.$items
            .dropFirst()  // 跳过初始空值
            .first()
            .sink { items in
                if !items.isEmpty { expectation.fulfill() }
            }
            .store(in: &cancellables)

        manager.start()
        pasteboard.copy("自动保存测试")

        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(manager.items.first?.content, .text("自动保存测试"))
        XCTAssertEqual(
            store.snapshotFetchCount,
            initialSnapshotFetchCount,
            "新增记录应增量更新发布列表，不应重新读取整份历史"
        )
    }

    func test_currentItemForBatchPaste_returnsExistingContentWithoutLaterDuplicateCapture() {
        let duplicateCapture = expectation(description: "当前内容不应在下一次轮询时重复进入批量列表")
        duplicateCapture.isInverted = true
        manager.capturedItem
            .sink { _ in duplicateCapture.fulfill() }
            .store(in: &cancellables)
        pasteboard.copy("批量首项")

        let item = manager.currentItemForBatchPaste()
        manager.start()

        waitForExpectations(timeout: 0.2)
        XCTAssertEqual(item?.content, .text("批量首项"))
        XCTAssertEqual(manager.items.map(\.content), [.text("批量首项")])
    }

    func test_multipleChanges_allSaved() {
        let expectation = expectation(description: "收到两条")

        manager.$items
            .dropFirst()
            .filter { $0.count >= 2 }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.start()
        pasteboard.copy("第一条")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pasteboard.copy("第二条")
        }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(manager.items.count, 2)
    }

    // MARK: - 去重

    func test_duplicateContent_isSkippedByDefault() {
        let expectation = expectation(description: "只保存一条")

        manager.start()
        pasteboard.copy("重复")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.pasteboard.copy("重复")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 1)
    }

    func test_deduplicateDisabled_allowsDuplicates() {
        let expectation = expectation(description: "保存两条重复")

        settings.deduplicateEnabled = false
        manager.start()
        pasteboard.copy("重复")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.pasteboard.copy("重复")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 2)
    }

    // MARK: - 上限管理

    func test_maxItems_enforcesLimitOnNewItems() {
        settings.maxItems = 2
        manager.start()

        let expectation = expectation(description: "裁剪完成")

        pasteboard.copy("A")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pasteboard.copy("B")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            self.pasteboard.copy("C")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        XCTAssertLessThanOrEqual(manager.items.count, 2)
    }

    func test_setMaxItems_immediatelyTrimsExisting() {
        // 先存入 5 条
        for i in 1...5 {
            store.add(
                ClipboardItem(
                    timestamp: Date(timeIntervalSinceNow: Double(i)),
                    content: .text("\(i)")
                ),
                deduplicate: false
            )
        }
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        XCTAssertEqual(manager.items.count, 5)

        // @Published 在 willSet 触发，需等待 DispatchQueue.main async 调度完成后再读取结果
        let exp = expectation(description: "裁剪至 3 条")
        manager.$items
            .filter { $0.count == 3 }
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        settings.maxItems = 3

        waitForExpectations(timeout: 1)
        XCTAssertEqual(manager.items.count, 3)
    }

    func test_init_appliesPersistedMaxItemsImmediately() {
        defaults.set(2, forKey: AppSettings.Keys.maxItems)
        let persistedSettings = AppSettings(defaults: defaults)

        for i in 1...4 {
            store.add(ClipboardItem(content: .text("\(i)")), deduplicate: false)
        }

        let freshManager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: persistedSettings
        )

        XCTAssertEqual(freshManager.items.count, 2)
    }

    func test_init_appliesPersistedRetentionDaysImmediately() {
        defaults.set(7, forKey: AppSettings.Keys.retentionDays)
        let persistedSettings = AppSettings(defaults: defaults)
        store.add(
            ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 8), content: .text("过期")),
            deduplicate: false
        )
        store.add(ClipboardItem(content: .text("保留")), deduplicate: false)

        let freshManager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: persistedSettings
        )

        XCTAssertEqual(freshManager.items.map(\.content), [.text("保留")])
    }

    func test_init_appliesPersistedMaxTotalSizeImmediately() {
        defaults.set(1, forKey: AppSettings.Keys.maxTotalSizeMB)
        let persistedSettings = AppSettings(defaults: defaults)
        let oversized = String(repeating: "A", count: 700_000)
        let newer = String(repeating: "B", count: 600_000)
        store.add(
            ClipboardItem(timestamp: Date(timeIntervalSince1970: 1), content: .text(oversized)),
            deduplicate: false
        )
        store.add(
            ClipboardItem(timestamp: Date(timeIntervalSince1970: 2), content: .text(newer)),
            deduplicate: false
        )

        let freshManager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: persistedSettings
        )

        XCTAssertEqual(freshManager.items.count, 1)
        XCTAssertEqual(freshManager.items.first?.content, .text(newer))
    }

    // MARK: - copyToPasteboard 不触发重复

    func test_copyToPasteboard_doesNotCreateDuplicateItem() {
        let item = ClipboardItem(content: .text("已有内容"))
        store.add(item)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)
        manager.start()

        XCTAssertEqual(manager.items.count, 1)

        manager.copyToPasteboard(item)

        let expectation = expectation(description: "等待轮询周期")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 1)
    }

    func test_copyToPasteboardAsPlainText_stripsRichTextFormats() {
        let item = ClipboardItem(
            content: .text("plain text"),
            richData: [NSPasteboard.PasteboardType.rtf.rawValue: Data("rich text".utf8)]
        )

        XCTAssertTrue(manager.copyToPasteboardAsPlainText(item))

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "plain text")
        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
    }

    func test_copyToPasteboard_materializesImageSummaryBeforeWriting() throws {
        let originalData = Data(repeating: 0xEF, count: 2 * 1_048_576)
        let originalItem = ClipboardItem(content: .image(originalData))
        store.add(originalItem)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)
        let summary = try XCTUnwrap(manager.items.first)

        guard case .image(let previewData) = summary.content else {
            return XCTFail("历史条目应保留图片类型")
        }
        XCTAssertLessThan(previewData.count, originalData.count)

        manager.copyToPasteboard(summary)

        XCTAssertEqual(NSPasteboard.general.data(forType: .tiff), originalData)
    }

    // MARK: - 删除

    func test_delete_removesItemAndUpdatesPublished() {
        let item = ClipboardItem(content: .text("要删除的"))
        store.add(item)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        XCTAssertEqual(manager.items.count, 1)

        manager.delete(item)

        XCTAssertEqual(manager.items.count, 0)
    }

    func test_deleteAll_clearsItemsAndUpdatesPublished() {
        store.add(ClipboardItem(content: .text("A")))
        store.add(ClipboardItem(content: .text("B")), deduplicate: false)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        XCTAssertEqual(manager.items.count, 2)

        manager.deleteAll()

        XCTAssertEqual(manager.items.count, 0)
    }

    // MARK: - 搜索

    func test_search_returnsMatchingItems() {
        store.add(ClipboardItem(content: .text("Hello World")))
        store.add(ClipboardItem(content: .text("你好")), deduplicate: false)

        let results = manager.search(query: "Hello")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, .text("Hello World"))
    }

    // MARK: - 生命周期

    func test_stop_preventsNewItemsFromBeingSaved() {
        let expectation = expectation(description: "stop 后不保存")
        expectation.isInverted = true

        manager.start()
        manager.stop()

        manager.$items
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        pasteboard.copy("stop 后的内容")

        waitForExpectations(timeout: 0.3)

        XCTAssertEqual(manager.items.count, 0)
    }

    // MARK: - 初始化加载

    func test_init_loadsExistingItemsFromStore() {
        store.add(ClipboardItem(content: .text("已有数据")))

        let freshManager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        XCTAssertEqual(freshManager.items.count, 1)
        XCTAssertEqual(freshManager.items.first?.content, .text("已有数据"))
    }

    // MARK: - 黑名单过滤

    func test_blacklist_itemFromBlockedApp_isNotSaved() {
        let blockedID = "com.example.blocked"
        settings.addBlockedApp(bundleID: blockedID)
        let sourceProvider = MockClipboardSourceProvider(bundleID: blockedID)
        manager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: settings,
            clipboardSourceProvider: sourceProvider
        )

        let expectation = expectation(description: "等待轮询周期")
        manager.start()
        pasteboard.copy("黑名单内容")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 0, "来自黑名单应用的内容不应被记录")
    }

    func test_blacklist_itemFromAllowedApp_isSaved() {
        settings.addBlockedApp(bundleID: "com.example.blocked")
        let sourceProvider = MockClipboardSourceProvider(bundleID: "com.example.allowed")
        manager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: settings,
            clipboardSourceProvider: sourceProvider
        )

        let expectation = expectation(description: "等待保存")
        manager.$items.dropFirst().first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        manager.start()
        pasteboard.copy("允许内容")
        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 1)
    }

    func test_blacklist_noFrontmostApp_itemIsSaved() {
        settings.addBlockedApp(bundleID: "com.example.blocked")
        let sourceProvider = MockClipboardSourceProvider(bundleID: nil)
        manager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: settings,
            clipboardSourceProvider: sourceProvider
        )

        let expectation = expectation(description: "等待保存")
        manager.$items.dropFirst().first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        manager.start()
        pasteboard.copy("无来源内容")
        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 1, "无法确定来源时应正常记录")
    }

    func test_recordingPause_manualPause_preventsNewItemsFromBeingSaved() {
        settings.pauseRecordingManually()

        let expectation = expectation(description: "等待轮询周期")
        manager.start()
        pasteboard.copy("暂停期间内容")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(manager.items.count, 0)
    }

    func test_recordingPause_stillPublishesCapturedItemForBatchMode() {
        settings.pauseRecordingManually()
        let captured = expectation(description: "批量模式仍收到内容")
        var receivedItem: ClipboardItem?
        manager.capturedItem
            .first()
            .sink {
                receivedItem = $0
                captured.fulfill()
            }
            .store(in: &cancellables)

        manager.start()
        pasteboard.copy("只进入批量队列")

        waitForExpectations(timeout: 1)
        XCTAssertEqual(receivedItem?.content, .text("只进入批量队列"))
        XCTAssertTrue(manager.items.isEmpty)
    }

    func test_blacklist_doesNotPublishCapturedItemForBatchMode() {
        let blockedID = "com.example.blocked"
        settings.addBlockedApp(bundleID: blockedID)
        manager = ClipboardManager(
            monitor: monitor,
            store: store,
            settings: settings,
            clipboardSourceProvider: MockClipboardSourceProvider(bundleID: blockedID)
        )
        let captured = expectation(description: "黑名单内容不进入批量队列")
        captured.isInverted = true
        manager.capturedItem
            .sink { _ in captured.fulfill() }
            .store(in: &cancellables)

        manager.start()
        pasteboard.copy("黑名单内容")

        waitForExpectations(timeout: 0.3)
    }

    // MARK: - 收藏功能

    func test_pin_movesItemToPinnedItems() {
        let item = ClipboardItem(content: .text("收藏我"))
        store.add(item)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        manager.pin(item, key: "example")

        XCTAssertTrue(manager.pinnedItems.contains { $0.id == item.id })
        XCTAssertFalse(manager.unpinnedItems.contains { $0.id == item.id })
        XCTAssertEqual(manager.items.first?.favoriteKey, "example")
        XCTAssertEqual(manager.pinnedItems.first?.favoriteKey, "example")
    }

    func test_favoriteKeyEdits_publishImmediatelyWithoutReloadingHistory() {
        let item = ClipboardItem(content: .text("a@example.com"))
        store.add(item)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)
        let fetchCount = store.snapshotFetchCount

        XCTAssertTrue(manager.pin(item, key: "  email  "))
        XCTAssertEqual(manager.searchPinned(query: "MAIL").map(\.id), [item.id])
        XCTAssertTrue(manager.updateFavoriteKey(item, key: "work"))
        XCTAssertEqual(manager.pinnedItems.first?.favoriteKey, "work")
        XCTAssertEqual(manager.items.first?.favoriteKey, "work")
        XCTAssertTrue(manager.searchPinned(query: "email").isEmpty)
        XCTAssertEqual(manager.searchPinned(query: "work").map(\.id), [item.id])

        manager.unpin(item)

        XCTAssertNil(manager.unpinnedItems.first?.favoriteKey)
        XCTAssertTrue(manager.pinnedItems.isEmpty)
        XCTAssertEqual(store.snapshotFetchCount, fetchCount)
    }

    func test_pin_rejectsEmptyKeyAndMissingHistoryRecordWithoutPublishingFavorites() {
        let item = ClipboardItem(content: .text("value"))
        store.add(item)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        XCTAssertFalse(manager.pin(item, key: " \n\t"))
        XCTAssertTrue(manager.pinnedItems.isEmpty)
        XCTAssertEqual(manager.unpinnedItems.map(\.id), [item.id])
        manager.delete(item)
        XCTAssertFalse(manager.pin(item, key: "key"))
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertTrue(manager.pinnedItems.isEmpty)
    }

    func test_unpin_movesItemToUnpinnedItems() {
        let item = ClipboardItem(content: .text("取消收藏"))
        store.add(item)
        store.pin(id: item.id)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        manager.unpin(item)

        XCTAssertFalse(manager.pinnedItems.contains { $0.id == item.id })
        XCTAssertTrue(manager.unpinnedItems.contains { $0.id == item.id })
    }

    func test_init_populatesPinnedAndUnpinnedSeparately() {
        let pinned = ClipboardItem(content: .text("收藏"))
        let unpinned = ClipboardItem(content: .text("未收藏"))
        store.add(pinned)
        store.add(unpinned, deduplicate: false)
        store.pin(id: pinned.id)

        let freshManager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        XCTAssertEqual(freshManager.pinnedItems.count, 1)
        XCTAssertEqual(freshManager.unpinnedItems.count, 1)
    }

    func test_deleteAll_preservesPinnedItems() {
        let pinned = ClipboardItem(content: .text("保留"))
        let unpinned = ClipboardItem(content: .text("删除"))
        store.add(pinned)
        store.add(unpinned, deduplicate: false)
        store.pin(id: pinned.id)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        manager.deleteAll()

        XCTAssertEqual(manager.pinnedItems.count, 1)
        XCTAssertEqual(manager.unpinnedItems.count, 0)
    }

    func test_searchPinned_returnsMatchingPinnedItems() {
        let pinned = ClipboardItem(content: .text("Swift 收藏"))
        store.add(pinned)
        store.pin(id: pinned.id)
        store.add(ClipboardItem(content: .text("Swift 未收藏")), deduplicate: false)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        let results = manager.searchPinned(query: "Swift")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, pinned.id)
    }

    func test_searchUnpinned_returnsMatchingUnpinnedItems() {
        let unpinned = ClipboardItem(content: .text("Swift 未收藏"))
        store.add(unpinned)
        let pinned = ClipboardItem(content: .text("Swift 收藏"))
        store.add(pinned, deduplicate: false)
        store.pin(id: pinned.id)
        manager = ClipboardManager(monitor: monitor, store: store, settings: settings)

        let results = manager.searchUnpinned(query: "Swift")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, unpinned.id)
    }
}

private struct MockClipboardSourceProvider: ClipboardSourceProviding {
    let bundleID: String?
    var currentSourceBundleID: String? { bundleID }
}
