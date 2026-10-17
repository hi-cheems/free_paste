//
//  ClipboardHistoryStoreTests.swift
//  FreePasteTests
//
//  Created by bond cheems on 2026/3/13.
//

import AppKit
import CoreData
import XCTest
@testable import FreePaste

final class ClipboardHistoryStoreTests: XCTestCase {

    private var store: ClipboardHistoryStore!

    override func setUp() {
        super.setUp()
        store = ClipboardHistoryStore(inMemory: true)
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - 基础增删查

    func test_add_thenFetchAll_returnsItem() {
        let item = ClipboardItem(content: .text("Hello"))
        store.add(item)

        let results = store.fetchAll()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, .text("Hello"))
    }

    func test_fetchAll_returnsByTimestampDescending() {
        let older = ClipboardItem(timestamp: Date(timeIntervalSinceNow: -10), content: .text("旧"))
        let newer = ClipboardItem(timestamp: Date(timeIntervalSinceNow: -1), content: .text("新"))
        store.add(older)
        store.add(newer, deduplicate: false)

        let results = store.fetchAll()

        XCTAssertEqual(results.first?.content, .text("新"))
        XCTAssertEqual(results.last?.content, .text("旧"))
    }

    func test_delete_removesCorrectItem() {
        let a = ClipboardItem(content: .text("A"))
        let b = ClipboardItem(content: .text("B"))
        store.add(a)
        store.add(b, deduplicate: false)

        store.delete(id: a.id)

        let results = store.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, .text("B"))
    }

    func test_deleteAll_clearsEverything() {
        store.add(ClipboardItem(content: .text("A")))
        store.add(ClipboardItem(content: .text("B")), deduplicate: false)

        store.deleteAll()

        XCTAssertEqual(store.fetchAll().count, 0)
    }

    func test_count_reflectsStoredItems() {
        XCTAssertEqual(store.count, 0)
        store.add(ClipboardItem(content: .text("X")))
        XCTAssertEqual(store.count, 1)
    }

    // MARK: - 去重

    func test_add_duplicateContent_replacesOldEntry() {
        let first = ClipboardItem(content: .text("同样的内容"))
        let second = ClipboardItem(content: .text("同样的内容"))
        store.add(first)
        store.add(second)  // 默认 deduplicate: true

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.fetchAll().first?.id, second.id)
    }

    func test_add_sameContentAfterDifferentContent_removesOldAndAddsNew() {
        let a1 = ClipboardItem(timestamp: Date(timeIntervalSinceNow: -2), content: .text("A"))
        store.add(a1)
        store.add(ClipboardItem(timestamp: Date(timeIntervalSinceNow: -1), content: .text("B")))
        let a2 = ClipboardItem(content: .text("A"))
        store.add(a2)  // 旧的 A 应被删除，新 A 在最前

        XCTAssertEqual(store.count, 2)
        let results = store.fetchAll()
        XCTAssertEqual(results.first?.content, .text("A"))
        XCTAssertEqual(results.first?.id, a2.id)
        XCTAssertEqual(results.last?.content, .text("B"))
    }

    func test_add_duplicateFileURLs_replacesOldEntry() {
        let urls = [URL(fileURLWithPath: "/sub")]
        let first = ClipboardItem(content: .fileURLs(urls))
        let second = ClipboardItem(content: .fileURLs(urls))
        store.add(first)
        store.add(second)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.fetchAll().first?.id, second.id)
        XCTAssertEqual(store.fetchAll().first?.content, .fileURLs(urls))
    }

    func test_add_withDeduplicateFalse_allowsDuplicates() {
        store.add(ClipboardItem(content: .text("重复")))
        store.add(ClipboardItem(content: .text("重复")), deduplicate: false)

        XCTAssertEqual(store.count, 2)
    }

    // MARK: - 上限裁剪

    func test_enforceLimit_removesOldestItems() {
        for i in 1...5 {
            let item = ClipboardItem(
                timestamp: Date(timeIntervalSinceNow: Double(i)),
                content: .text("条目 \(i)")
            )
            store.add(item, deduplicate: false)
        }

        store.enforceLimit(3)

        XCTAssertEqual(store.count, 3)
        // 保留最新的 3 条（条目 5、4、3）
        let results = store.fetchAll()
        XCTAssertEqual(results[0].content, .text("条目 5"))
        XCTAssertEqual(results[2].content, .text("条目 3"))
    }

    func test_enforceLimit_whenBelowLimit_doesNothing() {
        store.add(ClipboardItem(content: .text("仅一条")))

        store.enforceLimit(10)

        XCTAssertEqual(store.count, 1)
    }

    func test_enforceLimit_zero_doesNothing() {
        store.add(ClipboardItem(content: .text("内容")))

        store.enforceLimit(0)  // 0 表示不限制

        XCTAssertEqual(store.count, 1)
    }

    func test_deleteItemsOlderThan_removesExpiredEntries() {
        let expired = ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 8), content: .text("过期"))
        let fresh = ClipboardItem(timestamp: Date(), content: .text("保留"))
        store.add(expired)
        store.add(fresh, deduplicate: false)

        store.deleteItems(olderThan: Date(timeIntervalSinceNow: -3600 * 24 * 7))

        let results = store.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, .text("保留"))
    }

    func test_enforceTotalTextByteLimit_removesOldestItemsFirst() {
        store.add(ClipboardItem(timestamp: Date(timeIntervalSince1970: 1), content: .text("AAAA")), deduplicate: false)
        store.add(ClipboardItem(timestamp: Date(timeIntervalSince1970: 2), content: .text("BBBB")), deduplicate: false)
        store.add(ClipboardItem(timestamp: Date(timeIntervalSince1970: 3), content: .text("CCCC")), deduplicate: false)

        store.enforceTotalTextByteLimit(8)

        let results = store.fetchAll()
        XCTAssertEqual(results.map(\.content), [.text("CCCC"), .text("BBBB")])
    }

    func test_pruneHistory_appliesExpirationThenCountThenSize() {
        store.add(ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 10), content: .text("old")), deduplicate: false)
        store.add(ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 6), content: .text("1111")), deduplicate: false)
        store.add(ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 5), content: .text("2222")), deduplicate: false)
        store.add(ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 4), content: .text("3333")), deduplicate: false)

        store.pruneHistory(
            maxCount: 2,
            maxTotalTextBytes: 4,
            removingItemsOlderThan: Date(timeIntervalSinceNow: -3600 * 24 * 7)
        )

        let results = store.fetchAll()
        XCTAssertEqual(results.map(\.content), [.text("3333")])
    }

    func test_pruneHistory_countsRichTextPayloadBytes() {
        let older = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 1),
            content: .text("A"),
            richData: ["public.rtf": Data(repeating: 0x41, count: 16)]
        )
        let newer = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 2),
            content: .text("B")
        )
        store.add(older, deduplicate: false)
        store.add(newer, deduplicate: false)

        store.pruneHistory(
            maxCount: 0,
            maxTotalTextBytes: 8,
            removingItemsOlderThan: nil
        )

        XCTAssertEqual(store.fetchAll().map(\.id), [newer.id])
    }

    func test_fetchSnapshot_keepsLargePayloadsOutOfPublishedHistory() throws {
        let imageData = Data(repeating: 0xAB, count: 2 * 1_048_576)
        let richData = ["public.rtf": Data(repeating: 0xCD, count: 1_048_576)]
        let image = ClipboardItem(content: .image(imageData))
        let text = ClipboardItem(content: .text("摘要文本"), richData: richData)
        store.add(image, deduplicate: false)
        store.add(text, deduplicate: false)
        store.pin(id: text.id)

        let snapshot = store.fetchSnapshot()

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.unpinnedItems.map(\.id), [image.id])
        XCTAssertEqual(snapshot.pinnedItems.map(\.id), [text.id])

        let imageSummary = try XCTUnwrap(snapshot.items.first { $0.id == image.id })
        guard case .image(let previewData) = imageSummary.content else {
            return XCTFail("图片摘要应保留图片类型")
        }
        XCTAssertLessThan(previewData.count, imageData.count)
        XCTAssertEqual(imageSummary.payloadAvailability, .summary)

        let textSummary = try XCTUnwrap(snapshot.items.first { $0.id == text.id })
        XCTAssertNil(textSummary.richData)
        XCTAssertEqual(textSummary.payloadAvailability, .summary)

        let materializedImage = try XCTUnwrap(store.fetch(id: image.id))
        XCTAssertEqual(materializedImage.content, .image(imageData))
        XCTAssertEqual(materializedImage.payloadAvailability, .complete)

        let materializedText = try XCTUnwrap(store.fetch(id: text.id))
        XCTAssertEqual(materializedText.richData, richData)
        XCTAssertEqual(materializedText.payloadAvailability, .complete)
    }

    func test_fetchSnapshot_largeImageArchiveHasBoundedPublishedPayload() {
        let payload = Data(repeating: 0x7F, count: 1_048_576)
        for index in 0..<64 {
            store.add(
                ClipboardItem(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    content: .image(payload)
                ),
                deduplicate: false
            )
        }

        let snapshot = store.fetchSnapshot()
        let publishedImageBytes = snapshot.items.reduce(0) { total, item in
            guard case .image(let data) = item.content else { return total }
            return total + data.count
        }

        XCTAssertEqual(snapshot.items.count, 64)
        XCTAssertLessThan(publishedImageBytes, 1_048_576)
    }

    func test_imageThumbnail_isDownsampledToConfiguredPixelBound() throws {
        let imageData = try XCTUnwrap(makeTestImageData(width: 2_048, height: 1_024))

        let preview = try XCTUnwrap(ClipboardImageThumbnail.makePreview(from: imageData))
        let previewImage = try XCTUnwrap(NSImage(data: preview.data))

        XCTAssertGreaterThanOrEqual(preview.originalPixelSize.width, 2_048)
        XCTAssertEqual(
            preview.originalPixelSize.width / preview.originalPixelSize.height,
            2,
            accuracy: 0.01
        )
        XCTAssertLessThanOrEqual(
            max(previewImage.size.width, previewImage.size.height),
            CGFloat(ClipboardImageThumbnail.storedMaximumPixelDimension)
        )
    }

    func test_existingSQLiteStore_migratesWithoutLosingHistoryAndBackfillsThumbnail() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteMigrationTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let storeURL = directoryURL.appendingPathComponent("FreePaste.sqlite")
        let originalImageData = try XCTUnwrap(makeTestImageData())

        let oldContainer = NSPersistentContainer(
            name: "FreePaste",
            managedObjectModel: makeLegacyManagedObjectModel()
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        oldContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        oldContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        let entry = NSEntityDescription.insertNewObject(
            forEntityName: "ClipboardEntry",
            into: oldContainer.viewContext
        )
        let itemID = UUID()
        entry.setValue(itemID, forKey: "id")
        entry.setValue(Date(), forKey: "timestamp")
        entry.setValue(false, forKey: "isPinned")
        entry.setValue(originalImageData, forKey: "imageData")
        try oldContainer.viewContext.save()
        if let persistentStore = oldContainer.persistentStoreCoordinator.persistentStores.first {
            try oldContainer.persistentStoreCoordinator.remove(persistentStore)
        }

        let migratedStore = ClipboardHistoryStore(storeURL: storeURL)

        XCTAssertEqual(migratedStore.count, 1)
        XCTAssertEqual(migratedStore.fetch(id: itemID)?.content, .image(originalImageData))
        guard case .image(let initialPreviewData) = migratedStore.fetchSnapshot().items.first?.content else {
            return XCTFail("迁移后的条目应保留图片类型")
        }
        XCTAssertTrue(initialPreviewData.isEmpty)

        let backfillFinished = expectation(description: "旧图片元数据补全")
        migratedStore.prepareLegacyMetadataBatch { processedEntries, summariesChanged, mayHaveMore in
            XCTAssertTrue(processedEntries)
            XCTAssertTrue(summariesChanged)
            XCTAssertFalse(mayHaveMore)
            backfillFinished.fulfill()
        }
        waitForExpectations(timeout: 2)

        guard case .image(let previewData) = migratedStore.fetchSnapshot().items.first?.content else {
            return XCTFail("补全后仍应是图片摘要")
        }
        XCTAssertFalse(previewData.isEmpty)
        XCTAssertLessThan(previewData.count, originalImageData.count)
    }

    // MARK: - 搜索

    func test_searchPinned_prioritizesKeyMatchesAndPreservesOrderWithinGroups() {
        let keyOlder = ClipboardItem(timestamp: Date(timeIntervalSince1970: 1), content: .text("a@example.com"))
        let keyNewer = ClipboardItem(timestamp: Date(timeIntervalSince1970: 2), content: .text("email and key"))
        let valueOlder = ClipboardItem(timestamp: Date(timeIntervalSince1970: 3), content: .text("email value older"))
        let valueNewer = ClipboardItem(timestamp: Date(timeIntervalSince1970: 4), content: .text("email value newer"))
        let unpinned = ClipboardItem(timestamp: Date(timeIntervalSince1970: 5), content: .text("email history"))
        for item in [keyOlder, keyNewer, valueOlder, valueNewer, unpinned] {
            store.add(item, deduplicate: false)
        }
        store.pin(id: keyOlder.id, key: "work EMAIL")
        store.pin(id: keyNewer.id, key: "work EMAIL")
        store.pin(id: valueOlder.id)
        store.pin(id: valueNewer.id, key: "other")

        XCTAssertEqual(
            store.searchPinned(query: "mail").map(\.id),
            [keyNewer.id, keyOlder.id, valueNewer.id, valueOlder.id]
        )
        XCTAssertEqual(
            store.searchPinned(query: "EMAIL").map(\.id),
            [keyNewer.id, keyOlder.id, valueNewer.id, valueOlder.id]
        )
        XCTAssertEqual(
            store.searchPinned(query: "").map(\.id),
            [valueNewer.id, valueOlder.id, keyNewer.id, keyOlder.id]
        )
        XCTAssertEqual(store.searchUnpinned(query: "email").map(\.id), [unpinned.id])
        XCTAssertTrue(store.searchUnpinned(query: "work").isEmpty)
        XCTAssertEqual(store.search(query: "work").map(\.id), [keyNewer.id, keyOlder.id])
        XCTAssertEqual(
            store.search(query: "EMAIL").map(\.id),
            [keyNewer.id, keyOlder.id, unpinned.id, valueNewer.id, valueOlder.id]
        )
        XCTAssertEqual(store.search(query: "").map(\.id), [unpinned.id, valueNewer.id, valueOlder.id, keyNewer.id, keyOlder.id])
    }

    func test_favoriteKeys_supportImagesFilesAndValueSearchWithoutLoadingOriginalPayloads() throws {
        let imageData = Data(repeating: 0xAB, count: 1_048_576)
        let image = ClipboardItem(timestamp: Date(timeIntervalSince1970: 1), content: .image(imageData))
        let file = ClipboardItem(timestamp: Date(timeIntervalSince1970: 2), content: .fileURLs([
            URL(fileURLWithPath: "/tmp/email.pdf"),
        ]))
        store.add(image)
        store.add(file)
        store.pin(id: image.id, key: "email")
        store.pin(id: file.id, key: "documents")

        let matches = store.searchPinned(query: "email")

        XCTAssertEqual(matches.map(\.id), [image.id, file.id])
        XCTAssertEqual(matches.first?.payloadAvailability, .summary)
        XCTAssertEqual(matches.first?.favoriteKey, "email")
        guard case .image(let summaryData) = matches.first?.content else {
            return XCTFail("Key 搜索应返回图片摘要")
        }
        XCTAssertLessThan(summaryData.count, imageData.count)
        XCTAssertEqual(store.fetch(id: image.id)?.content, .image(imageData))
        XCTAssertEqual(store.fetch(id: image.id)?.favoriteKey, "email")
        XCTAssertEqual(store.search(query: "email").map(\.id), [image.id, file.id])
    }

    func test_editFavoriteKey_updatesSearchWithoutChangingValueOrTimestamp() throws {
        let item = ClipboardItem(content: .text("a@example.com"), richData: ["public.rtf": Data([1, 2, 3])])
        store.add(item)
        store.pin(id: item.id, key: "old")

        XCTAssertTrue(store.updateFavoriteKey(id: item.id, key: "  email 工作  \n"))

        XCTAssertTrue(store.searchPinned(query: "old").isEmpty)
        XCTAssertEqual(store.searchPinned(query: "工作").map(\.id), [item.id])
        let result = try XCTUnwrap(store.fetch(id: item.id))
        XCTAssertEqual(result.favoriteKey, "email 工作")
        XCTAssertEqual(result.content, item.content)
        XCTAssertEqual(result.richData, item.richData)
        XCTAssertEqual(result.timestamp, item.timestamp)

        XCTAssertTrue(store.updateFavoriteKey(id: item.id, key: " \n"))
        XCTAssertNil(store.fetch(id: item.id)?.favoriteKey)
        XCTAssertEqual(store.searchPinned(query: "example").map(\.id), [item.id])
        XCTAssertTrue(store.searchPinned(query: "工作").isEmpty)
    }

    func test_newFavorite_rejectsBlankKeyAndUnpinClearsKey() {
        let item = ClipboardItem(content: .text("value"))
        store.add(item)

        XCTAssertFalse(store.pin(id: item.id, key: " \n\t"))
        XCTAssertTrue(store.fetchPinned().isEmpty)
        XCTAssertFalse(store.updateFavoriteKey(id: item.id, key: "email"))
        XCTAssertTrue(store.pin(id: item.id, key: "  email  "))
        XCTAssertEqual(store.fetchSnapshot().pinnedItems.first?.favoriteKey, "email")

        store.unpin(id: item.id)

        XCTAssertNil(store.fetch(id: item.id)?.favoriteKey)
        XCTAssertTrue(store.searchPinned(query: "email").isEmpty)
        XCTAssertEqual(store.fetchUnpinned().map(\.id), [item.id])
    }

    func test_favoriteKey_persistsAcrossStoreReopening() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteKeyTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("FreePaste.sqlite")
        let item = ClipboardItem(content: .text("a@example.com"))
        autoreleasepool {
            let firstStore = ClipboardHistoryStore(storeURL: url)
            firstStore.add(item)
            XCTAssertTrue(firstStore.pin(id: item.id, key: "email"))
        }
        let reopenedStore = ClipboardHistoryStore(storeURL: url)
        XCTAssertEqual(reopenedStore.searchPinned(query: "MAIL").map(\.id), [item.id])
        XCTAssertEqual(reopenedStore.fetchSnapshot().pinnedItems.first?.favoriteKey, "email")
    }

    func test_preKeySQLiteStore_migratesAllContentAndFavoritesFromLegacyLocationWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePastePreKeyTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("FreePaste.sqlite")
        let imageID = UUID()
        let textID = UUID()
        let fileID = UUID()
        let imageData = Data(repeating: 0xAB, count: 2 * 1_048_576)
        let richData = ["public.rtf": Data(repeating: 0xCD, count: 1_048_576)]
        let richBlob = try PropertyListSerialization.data(fromPropertyList: richData, format: .binary, options: 0)
        let fileURLs = [URL(fileURLWithPath: "/tmp/legacy.pdf")]
        let fileJSON = String(data: try JSONEncoder().encode(fileURLs.map(\.absoluteString)), encoding: .utf8)!
        let oldContainer = NSPersistentContainer(name: "FreePaste", managedObjectModel: makeLegacyManagedObjectModel(includeMetadata: true))
        oldContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var loadError: Error?
        oldContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        for (id, property, value) in [(imageID, "imageData", imageData as Any), (textID, "text", "legacy email" as Any), (fileID, "fileURLsJSON", fileJSON as Any)] {
            let entry = NSEntityDescription.insertNewObject(forEntityName: "ClipboardEntry", into: oldContainer.viewContext)
            entry.setValue(id, forKey: "id")
            entry.setValue(Date(timeIntervalSince1970: 100), forKey: "timestamp")
            entry.setValue(id != fileID, forKey: "isPinned")
            entry.setValue(value, forKey: property)
            entry.setValue(true, forKey: "metadataPrepared")
            if id == textID { entry.setValue(richBlob, forKey: "richDataBlob") }
        }
        try oldContainer.viewContext.save()
        try oldContainer.persistentStoreCoordinator.remove(try XCTUnwrap(oldContainer.persistentStoreCoordinator.persistentStores.first))
        let originalBytes = try Data(contentsOf: url)

        let migratedStore = ClipboardHistoryStore(
            storeURL: directory.appendingPathComponent("Sandbox.sqlite"), legacyStoreURL: url
        )

        XCTAssertEqual(migratedStore.count, 3)
        XCTAssertEqual(Set(migratedStore.fetchSnapshot().pinnedItems.map(\.id)), Set([imageID, textID]))
        XCTAssertTrue(migratedStore.fetchSnapshot().pinnedItems.allSatisfy { $0.favoriteKey == nil })
        XCTAssertEqual(migratedStore.fetch(id: imageID)?.content, .image(imageData))
        XCTAssertEqual(migratedStore.fetch(id: textID)?.richData, richData)
        XCTAssertEqual(migratedStore.fetch(id: fileID)?.content, .fileURLs(fileURLs))
        XCTAssertEqual(migratedStore.searchPinned(query: "email").map(\.id), [textID])
        XCTAssertTrue(migratedStore.updateFavoriteKey(id: imageID, key: "image"))
        XCTAssertEqual(migratedStore.searchPinned(query: "IMAGE").map(\.id), [imageID])
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }

    func test_unreadableDatabase_isNotDeletedOrOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteInvalidStoreTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("FreePaste.sqlite")
        let originalBytes = Data("not a database".utf8)
        try originalBytes.write(to: url)

        let fallbackStore = ClipboardHistoryStore(storeURL: url)
        fallbackStore.add(ClipboardItem(content: .text("temporary")))

        XCTAssertEqual(fallbackStore.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }

    func test_search_returnsMatchingItems() {
        store.add(ClipboardItem(content: .text("Hello World")))
        store.add(ClipboardItem(content: .text("你好世界")), deduplicate: false)
        store.add(ClipboardItem(content: .text("Hello Swift")), deduplicate: false)

        let results = store.search(query: "Hello")

        XCTAssertEqual(results.count, 2)
    }

    func test_search_isCaseInsensitive() {
        store.add(ClipboardItem(content: .text("FreePaste")))

        let results = store.search(query: "freepaste")

        XCTAssertEqual(results.count, 1)
    }

    func test_search_emptyQuery_returnsAll() {
        store.add(ClipboardItem(content: .text("A")))
        store.add(ClipboardItem(content: .text("B")), deduplicate: false)

        let results = store.search(query: "")

        XCTAssertEqual(results.count, 2)
    }

    func test_search_noMatch_returnsEmpty() {
        store.add(ClipboardItem(content: .text("苹果")))

        let results = store.search(query: "香蕉")

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - fetchAll limit

    func test_fetchAll_withLimit_returnsAtMostNItems() {
        for i in 1...5 {
            store.add(ClipboardItem(content: .text("\(i)")), deduplicate: false)
        }

        let results = store.fetchAll(limit: 3)

        XCTAssertEqual(results.count, 3)
    }

    // MARK: - 数据完整性

    func test_add_preservesIdAndTimestamp() throws {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1000000)
        let item = ClipboardItem(id: id, timestamp: timestamp, content: .text("数据完整性"))

        store.add(item)

        let result = try XCTUnwrap(store.fetchAll().first)
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_defaultPersistentStoreURL_pointsToApplicationSupport() throws {
        let url = try ClipboardHistoryStore.defaultPersistentStoreURL()

        XCTAssertTrue(url.path.hasSuffix("/Library/Application Support/FreePaste/FreePaste.sqlite"))
    }

    func test_legacyLocationUpgrade_restoresHistoryFavoritesAndExternalPayloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteLocationTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("Legacy.sqlite")
        let destinationURL = directory.appendingPathComponent("Sandbox.sqlite")
        let text = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 100), content: .text("saved email"),
            richData: ["public.rtf": Data(repeating: 0xCD, count: 1_048_576)]
        )
        let image = ClipboardItem(content: .image(Data(repeating: 0xAB, count: 2 * 1_048_576)))
        let file = ClipboardItem(content: .fileURLs([URL(fileURLWithPath: "/tmp/saved.pdf")]))
        autoreleasepool {
            let legacy = ClipboardHistoryStore(storeURL: legacyURL)
            for item in [text, image, file] { legacy.add(item, deduplicate: false) }
            XCTAssertTrue(legacy.pin(id: text.id, key: "email"))
        }
        autoreleasepool { _ = ClipboardHistoryStore(storeURL: destinationURL) }
        let originalBytes = try Data(contentsOf: legacyURL)

        let upgraded = ClipboardHistoryStore(storeURL: destinationURL, legacyStoreURL: legacyURL)

        XCTAssertEqual(upgraded.count, 3)
        XCTAssertEqual(upgraded.fetch(id: text.id)?.timestamp, text.timestamp)
        XCTAssertEqual(upgraded.fetch(id: text.id)?.richData, text.richData)
        XCTAssertEqual(upgraded.searchPinned(query: "email").map(\.id), [text.id])
        XCTAssertEqual(upgraded.fetch(id: image.id)?.content, image.content)
        XCTAssertEqual(upgraded.fetch(id: file.id)?.content, file.content)
        XCTAssertEqual(try Data(contentsOf: legacyURL), originalBytes)
    }

    func test_legacyLocationUpgrade_mergesWithoutReplacingNewerRecordsAndDoesNotResurrectDeletedItems() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteMergeTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("Legacy.sqlite")
        let destinationURL = directory.appendingPathComponent("Sandbox.sqlite")
        let original = ClipboardItem(content: .text("original"))
        let missing = ClipboardItem(content: .text("missing"))
        let recent = ClipboardItem(content: .text("recent"))
        autoreleasepool {
            let legacy = ClipboardHistoryStore(storeURL: legacyURL)
            legacy.add(original)
            legacy.add(missing)
            let destination = ClipboardHistoryStore(storeURL: destinationURL)
            destination.add(ClipboardItem(id: original.id, content: .text("updated")))
            destination.add(recent)
        }
        autoreleasepool {
            let upgraded = ClipboardHistoryStore(storeURL: destinationURL, legacyStoreURL: legacyURL)
            XCTAssertEqual(upgraded.count, 3)
            XCTAssertEqual(upgraded.fetch(id: original.id)?.content, .text("updated"))
            XCTAssertEqual(upgraded.fetch(id: recent.id)?.content, recent.content)
            upgraded.delete(id: missing.id)
        }

        let reopened = ClipboardHistoryStore(storeURL: destinationURL, legacyStoreURL: legacyURL)

        XCTAssertEqual(reopened.count, 2)
        XCTAssertNil(reopened.fetch(id: missing.id))
    }

    func test_legacyLocationUpgrade_keepsCurrentHistoryWhenLegacyDatabaseIsInvalidAndRetriesLater() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteImportFailureTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("Legacy.sqlite")
        let destinationURL = directory.appendingPathComponent("Sandbox.sqlite")
        let originalBytes = Data("not a database".utf8)
        try originalBytes.write(to: legacyURL)
        let recent = ClipboardItem(content: .text("recent"))
        autoreleasepool {
            let destination = ClipboardHistoryStore(storeURL: destinationURL)
            destination.add(recent)
        }
        autoreleasepool {
            let upgraded = ClipboardHistoryStore(storeURL: destinationURL, legacyStoreURL: legacyURL)
            XCTAssertEqual(upgraded.fetch(id: recent.id)?.content, recent.content)
            XCTAssertEqual(try? Data(contentsOf: legacyURL), originalBytes)
        }
        try FileManager.default.removeItem(at: legacyURL)
        let missing = ClipboardItem(content: .text("missing"))
        autoreleasepool { _ = ClipboardHistoryStore(storeURL: legacyURL).add(missing) }

        let retried = ClipboardHistoryStore(storeURL: destinationURL, legacyStoreURL: legacyURL)

        XCTAssertEqual(retried.count, 2)
        XCTAssertEqual(retried.fetch(id: missing.id)?.content, missing.content)
    }

    func test_legacyLocationUpgrade_doesNotImportIntoMemoryOrSameLocation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePasteImportIsolationTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("Legacy.sqlite")
        let item = ClipboardItem(content: .text("saved"))
        autoreleasepool { _ = ClipboardHistoryStore(storeURL: legacyURL).add(item) }

        let memoryStore = ClipboardHistoryStore(inMemory: true, legacyStoreURL: legacyURL)
        let sameLocation = ClipboardHistoryStore(storeURL: legacyURL, legacyStoreURL: legacyURL)

        XCTAssertEqual(memoryStore.count, 0)
        XCTAssertEqual(sameLocation.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.appendingPathExtension("legacy-imported").path))
    }

    // MARK: - 收藏功能

    func test_pin_marksItemAsPinned() {
        let item = ClipboardItem(content: .text("收藏我"))
        store.add(item)

        store.pin(id: item.id)

        XCTAssertTrue(store.fetchPinned().first?.isPinned == true)
    }

    func test_unpin_marksItemAsUnpinned() {
        let item = ClipboardItem(content: .text("取消收藏"))
        store.add(item)
        store.pin(id: item.id)

        store.unpin(id: item.id)

        XCTAssertTrue(store.fetchUnpinned().contains { $0.id == item.id })
        XCTAssertFalse(store.fetchPinned().contains { $0.id == item.id })
    }

    func test_fetchPinned_returnsOnlyPinnedItems() {
        let pinned = ClipboardItem(content: .text("收藏"))
        let unpinned = ClipboardItem(content: .text("未收藏"))
        store.add(pinned)
        store.add(unpinned, deduplicate: false)
        store.pin(id: pinned.id)

        let results = store.fetchPinned()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, pinned.id)
    }

    func test_fetchUnpinned_returnsOnlyUnpinnedItems() {
        let pinned = ClipboardItem(content: .text("收藏"))
        let unpinned = ClipboardItem(content: .text("未收藏"))
        store.add(pinned)
        store.add(unpinned, deduplicate: false)
        store.pin(id: pinned.id)

        let results = store.fetchUnpinned()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, unpinned.id)
    }

    func test_searchPinned_returnsMatchingPinnedItems() {
        let pinned = ClipboardItem(content: .text("Swift 收藏"))
        let unpinned = ClipboardItem(content: .text("Swift 未收藏"))
        store.add(pinned)
        store.add(unpinned, deduplicate: false)
        store.pin(id: pinned.id)

        let results = store.searchPinned(query: "Swift")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, pinned.id)
    }

    func test_searchUnpinned_returnsMatchingUnpinnedItems() {
        let pinned = ClipboardItem(content: .text("Swift 收藏"))
        let unpinned = ClipboardItem(content: .text("Swift 未收藏"))
        store.add(pinned)
        store.add(unpinned, deduplicate: false)
        store.pin(id: pinned.id)

        let results = store.searchUnpinned(query: "Swift")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, unpinned.id)
    }

    func test_enforceLimit_skipsPinnedItems() {
        let pinned = ClipboardItem(timestamp: Date(timeIntervalSince1970: 1), content: .text("收藏"))
        store.add(pinned, deduplicate: false)
        store.pin(id: pinned.id)
        for i in 2...4 {
            store.add(ClipboardItem(timestamp: Date(timeIntervalSince1970: Double(i)), content: .text("条目\(i)")), deduplicate: false)
        }

        store.enforceLimit(1)

        XCTAssertTrue(store.fetchPinned().contains { $0.id == pinned.id }, "收藏项不应被 enforceLimit 删除")
        XCTAssertEqual(store.fetchUnpinned().count, 1)
    }

    func test_deleteAll_skipsPinnedItems() {
        let pinned = ClipboardItem(content: .text("保留我"))
        store.add(pinned)
        store.add(ClipboardItem(content: .text("删掉我")), deduplicate: false)
        store.pin(id: pinned.id)

        store.deleteAll()

        XCTAssertEqual(store.fetchPinned().count, 1)
        XCTAssertEqual(store.fetchUnpinned().count, 0)
    }

    func test_deleteItemsOlderThan_skipsPinnedItems() {
        let pinnedOld = ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 10), content: .text("老收藏"))
        store.add(pinnedOld)
        store.pin(id: pinnedOld.id)
        let unpinnedOld = ClipboardItem(timestamp: Date(timeIntervalSinceNow: -3600 * 24 * 10), content: .text("老未收藏"))
        store.add(unpinnedOld, deduplicate: false)

        store.deleteItems(olderThan: Date(timeIntervalSinceNow: -3600 * 24 * 7))

        XCTAssertEqual(store.fetchPinned().count, 1, "收藏项不应被过期清理删除")
        XCTAssertEqual(store.fetchUnpinned().count, 0)
    }

    func test_add_duplicateOfPinnedItem_doesNotDeletePinned() {
        let pinned = ClipboardItem(content: .text("相同内容"))
        store.add(pinned)
        store.pin(id: pinned.id)

        store.add(ClipboardItem(content: .text("相同内容")))

        XCTAssertTrue(store.fetchPinned().contains { $0.id == pinned.id }, "收藏项不应被去重删除")
        XCTAssertEqual(store.fetchUnpinned().count, 1, "新条目应被添加为未收藏")
    }

    private func makeTestImageData(width: CGFloat = 256, height: CGFloat = 128) -> Data? {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        return image.tiffRepresentation
    }

    private func makeLegacyManagedObjectModel(includeMetadata: Bool = false) -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "ClipboardEntry"
        entity.managedObjectClassName = "NSManagedObject"

        func attribute(
            _ name: String,
            _ type: NSAttributeType,
            optional: Bool = false,
            defaultValue: Any? = nil
        ) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            attribute.defaultValue = defaultValue
            return attribute
        }

        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("timestamp", .dateAttributeType),
            attribute("text", .stringAttributeType, optional: true),
            attribute("isPinned", .booleanAttributeType, defaultValue: false),
            attribute("imageData", .binaryDataAttributeType, optional: true),
            attribute("fileURLsJSON", .stringAttributeType, optional: true),
            attribute("richDataBlob", .binaryDataAttributeType, optional: true),
        ]
        if includeMetadata {
            entity.properties += [
                attribute("imageThumbnailData", .binaryDataAttributeType, optional: true),
                attribute("imagePixelWidth", .doubleAttributeType, optional: true),
                attribute("imagePixelHeight", .doubleAttributeType, optional: true),
                attribute("payloadByteCount", .integer64AttributeType, defaultValue: 0),
                attribute("metadataPrepared", .booleanAttributeType, defaultValue: false),
            ]
            entity.attributesByName["imageData"]?.allowsExternalBinaryDataStorage = true
            entity.attributesByName["richDataBlob"]?.allowsExternalBinaryDataStorage = true
            let attributes = entity.attributesByName
            entity.indexes = [
                NSFetchIndexDescription(name: "byID", elements: [NSFetchIndexElementDescription(property: attributes["id"]!, collationType: .binary)]),
                NSFetchIndexDescription(name: "byTimestamp", elements: [NSFetchIndexElementDescription(property: attributes["timestamp"]!, collationType: .binary)]),
                NSFetchIndexDescription(name: "byPinnedTimestamp", elements: [
                    NSFetchIndexElementDescription(property: attributes["isPinned"]!, collationType: .binary),
                    NSFetchIndexElementDescription(property: attributes["timestamp"]!, collationType: .binary),
                ]),
            ]
        }
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}
