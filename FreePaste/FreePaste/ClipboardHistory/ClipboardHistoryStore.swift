//
//  ClipboardHistoryStore.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/13.
//

import CoreData
import Darwin
import Foundation

struct ClipboardHistorySnapshot {
    let items: [ClipboardItem]
    let unpinnedItems: [ClipboardItem]
    let pinnedItems: [ClipboardItem]

    init(items: [ClipboardItem]) {
        self.items = items
        unpinnedItems = items.filter { !$0.isPinned }
        pinnedItems = items.filter(\.isPinned)
    }
}

struct ClipboardHistoryMutation {
    let insertedItem: ClipboardItem?
    let removedItemIDs: Set<UUID>
}

/// Core Data-backed clipboard history storage.
///
/// List queries return lightweight summaries. Original image and rich-text payloads stay in
/// SQLite until the selected item is pasted, which keeps long-running memory usage bounded.
final class ClipboardHistoryStore {
    private struct PruningRecord {
        let id: UUID
        let timestamp: Date
        let payloadByteCount: Int64
    }

    // MARK: - Core Data configuration

    private static let entityName = "ClipboardEntry"

    private static let model: NSManagedObjectModel = {
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = "NSManagedObject"

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType

        let timestampAttr = NSAttributeDescription()
        timestampAttr.name = "timestamp"
        timestampAttr.attributeType = .dateAttributeType

        let textAttr = NSAttributeDescription()
        textAttr.name = "text"
        textAttr.attributeType = .stringAttributeType
        textAttr.isOptional = true

        let isPinnedAttr = NSAttributeDescription()
        isPinnedAttr.name = "isPinned"
        isPinnedAttr.attributeType = .booleanAttributeType
        isPinnedAttr.defaultValue = false

        let favoriteKeyAttr = NSAttributeDescription()
        favoriteKeyAttr.name = "favoriteKey"
        favoriteKeyAttr.attributeType = .stringAttributeType
        favoriteKeyAttr.isOptional = true

        let imageDataAttr = NSAttributeDescription()
        imageDataAttr.name = "imageData"
        imageDataAttr.attributeType = .binaryDataAttributeType
        imageDataAttr.isOptional = true
        imageDataAttr.allowsExternalBinaryDataStorage = true

        let imageThumbnailDataAttr = NSAttributeDescription()
        imageThumbnailDataAttr.name = "imageThumbnailData"
        imageThumbnailDataAttr.attributeType = .binaryDataAttributeType
        imageThumbnailDataAttr.isOptional = true

        let imagePixelWidthAttr = NSAttributeDescription()
        imagePixelWidthAttr.name = "imagePixelWidth"
        imagePixelWidthAttr.attributeType = .doubleAttributeType
        imagePixelWidthAttr.isOptional = true

        let imagePixelHeightAttr = NSAttributeDescription()
        imagePixelHeightAttr.name = "imagePixelHeight"
        imagePixelHeightAttr.attributeType = .doubleAttributeType
        imagePixelHeightAttr.isOptional = true

        let fileURLsJSONAttr = NSAttributeDescription()
        fileURLsJSONAttr.name = "fileURLsJSON"
        fileURLsJSONAttr.attributeType = .stringAttributeType
        fileURLsJSONAttr.isOptional = true

        let richDataBlobAttr = NSAttributeDescription()
        richDataBlobAttr.name = "richDataBlob"
        richDataBlobAttr.attributeType = .binaryDataAttributeType
        richDataBlobAttr.isOptional = true
        richDataBlobAttr.allowsExternalBinaryDataStorage = true

        let payloadByteCountAttr = NSAttributeDescription()
        payloadByteCountAttr.name = "payloadByteCount"
        payloadByteCountAttr.attributeType = .integer64AttributeType
        payloadByteCountAttr.defaultValue = 0

        let metadataPreparedAttr = NSAttributeDescription()
        metadataPreparedAttr.name = "metadataPrepared"
        metadataPreparedAttr.attributeType = .booleanAttributeType
        metadataPreparedAttr.defaultValue = false

        entity.properties = [
            idAttr,
            timestampAttr,
            textAttr,
            isPinnedAttr,
            favoriteKeyAttr,
            imageDataAttr,
            imageThumbnailDataAttr,
            imagePixelWidthAttr,
            imagePixelHeightAttr,
            fileURLsJSONAttr,
            richDataBlobAttr,
            payloadByteCountAttr,
            metadataPreparedAttr,
        ]
        entity.indexes = [
            NSFetchIndexDescription(
                name: "byID",
                elements: [NSFetchIndexElementDescription(property: idAttr, collationType: .binary)]
            ),
            NSFetchIndexDescription(
                name: "byTimestamp",
                elements: [NSFetchIndexElementDescription(property: timestampAttr, collationType: .binary)]
            ),
            NSFetchIndexDescription(
                name: "byPinnedTimestamp",
                elements: [
                    NSFetchIndexElementDescription(property: isPinnedAttr, collationType: .binary),
                    NSFetchIndexElementDescription(property: timestampAttr, collationType: .binary),
                ]
            ),
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }()

    private let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }
    let persistentStoreURL: URL?
    #if DEBUG
    private(set) var snapshotFetchCount = 0
    #endif

    // MARK: - Initialization

    init(inMemory: Bool = false, storeURL: URL? = nil, legacyStoreURL: URL? = nil) {
        container = NSPersistentContainer(
            name: "FreePaste",
            managedObjectModel: Self.model
        )
        let description: NSPersistentStoreDescription
        if inMemory || storeURL != nil {
            description = NSPersistentStoreDescription()
        } else {
            description = container.persistentStoreDescriptions.first
                ?? NSPersistentStoreDescription()
        }
        container.persistentStoreDescriptions = [description]
        if inMemory {
            description.type = NSInMemoryStoreType
            let inMemoryURL = URL(fileURLWithPath: "/dev/null")
            description.url = inMemoryURL
            persistentStoreURL = inMemoryURL
        } else if let resolvedStoreURL = storeURL ?? (try? Self.defaultPersistentStoreURL()) {
            description.type = NSSQLiteStoreType
            description.url = resolvedStoreURL
            persistentStoreURL = resolvedStoreURL
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        } else {
            description.type = NSInMemoryStoreType
            description.url = nil
            persistentStoreURL = nil
        }

        var loadError: Error?
        if !inMemory, let storeURL = persistentStoreURL {
            do {
                try Self.migrateExistingStoreIfNeeded(at: storeURL)
            } catch {
                loadError = error
            }
        }
        if loadError == nil {
            container.loadPersistentStores { _, error in
                loadError = error
            }
        }

        if let loadError {
            print("FreePaste: Core Data 加载失败，保留原数据库并临时使用内存存储：\(loadError)")
            description.type = NSInMemoryStoreType
            description.url = nil
            container.loadPersistentStores { _, error in
                if let error {
                    print("FreePaste: Core Data 内存存储加载失败：\(error)")
                }
            }
        }

        context.undoManager = nil
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true

        if !inMemory,
           let sourceURL = legacyStoreURL ?? (storeURL == nil ? Self.legacyPersistentStoreURL() : nil) {
            do {
                try importLegacyHistoryIfNeeded(from: sourceURL)
            } catch {
                print("FreePaste: 旧目录历史迁移失败，保留原数据并在下次启动重试：\(error)")
            }
        }
    }

    // MARK: - Writes

    @discardableResult
    func add(_ item: ClipboardItem, deduplicate: Bool = true) -> ClipboardHistoryMutation {
        let deduplicatedIDs = deduplicate
            ? deleteUnpinnedEntries(matchingContentOf: item)
            : []

        let entry = NSManagedObject(
            entity: context.persistentStoreCoordinator!
                .managedObjectModel.entitiesByName[Self.entityName]!,
            insertInto: context
        )
        entry.setValue(item.id, forKey: "id")
        entry.setValue(item.timestamp, forKey: "timestamp")
        entry.setValue(item.isPinned, forKey: "isPinned")
        entry.setValue(item.favoriteKey, forKey: "favoriteKey")
        entry.setValue(true, forKey: "metadataPrepared")

        let payloadByteCount: Int
        let summary: ClipboardItem
        switch item.content {
        case .text(let text):
            entry.setValue(text, forKey: "text")
            var richBlob: Data?
            if let richData = item.richData, !richData.isEmpty {
                richBlob = try? PropertyListSerialization.data(
                    fromPropertyList: richData,
                    format: .binary,
                    options: 0
                )
                entry.setValue(richBlob, forKey: "richDataBlob")
            }
            payloadByteCount = text.lengthOfBytes(using: .utf8) + (richBlob?.count ?? 0)
            summary = ClipboardItem(
                id: item.id,
                timestamp: item.timestamp,
                content: .text(text),
                isPinned: item.isPinned,
                favoriteKey: item.favoriteKey,
                payloadAvailability: .summary
            )

        case .image(let data):
            entry.setValue(data, forKey: "imageData")
            let preview = autoreleasepool {
                ClipboardImageThumbnail.makePreview(from: data)
            }
            if let preview {
                entry.setValue(preview.data, forKey: "imageThumbnailData")
                entry.setValue(preview.originalPixelSize.width, forKey: "imagePixelWidth")
                entry.setValue(preview.originalPixelSize.height, forKey: "imagePixelHeight")
            }
            payloadByteCount = data.count
            summary = ClipboardItem(
                id: item.id,
                timestamp: item.timestamp,
                content: .image(preview?.data ?? Data()),
                isPinned: item.isPinned,
                favoriteKey: item.favoriteKey,
                payloadAvailability: .summary,
                imagePixelSize: preview?.originalPixelSize
            )

        case .fileURLs(let urls):
            let json = fileURLsJSONString(for: urls)
            entry.setValue(json, forKey: "fileURLsJSON")
            payloadByteCount = json?.lengthOfBytes(using: .utf8) ?? 0
            summary = ClipboardItem(
                id: item.id,
                timestamp: item.timestamp,
                content: .fileURLs(urls),
                isPinned: item.isPinned,
                favoriteKey: item.favoriteKey
            )
        }
        entry.setValue(Int64(payloadByteCount), forKey: "payloadByteCount")
        saveContext()
        return ClipboardHistoryMutation(
            insertedItem: summary,
            removedItemIDs: deduplicatedIDs
        )
    }

    @discardableResult
    func pin(id: UUID, key: String? = nil) -> Bool {
        let normalizedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if key != nil, normalizedKey?.isEmpty != false { return false }
        guard let entry = fetchEntry(by: id) else { return false }
        entry.setValue(true, forKey: "isPinned")
        entry.setValue(normalizedKey, forKey: "favoriteKey")
        return saveContext()
    }

    @discardableResult
    func unpin(id: UUID) -> Bool {
        guard let entry = fetchEntry(by: id) else { return false }
        entry.setValue(false, forKey: "isPinned")
        entry.setValue(nil, forKey: "favoriteKey")
        return saveContext()
    }

    @discardableResult
    func updateFavoriteKey(id: UUID, key: String) -> Bool {
        guard let entry = fetchEntry(by: id),
              entry.value(forKey: "isPinned") as? Bool == true else { return false }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.setValue(normalizedKey.isEmpty ? nil : normalizedKey, forKey: "favoriteKey")
        return saveContext()
    }

    @discardableResult
    func delete(id: UUID) -> Set<UUID> {
        deleteEntries(withIDs: [id])
        return [id]
    }

    @discardableResult
    func deleteAll() -> Set<UUID> {
        deleteEntries(matching: NSPredicate(format: "isPinned == NO"))
    }

    func enforceLimit(_ maxCount: Int) {
        guard maxCount > 0 else { return }
        pruneHistory(maxCount: maxCount, maxTotalTextBytes: 0, removingItemsOlderThan: nil)
    }

    func deleteItems(olderThan cutoffDate: Date) {
        pruneHistory(maxCount: 0, maxTotalTextBytes: 0, removingItemsOlderThan: cutoffDate)
    }

    func enforceTotalTextByteLimit(_ maxTotalTextBytes: Int) {
        guard maxTotalTextBytes > 0 else { return }
        pruneHistory(maxCount: 0, maxTotalTextBytes: maxTotalTextBytes, removingItemsOlderThan: nil)
    }

    /// Applies expiration, count, and byte limits in one metadata-only pass.
    @discardableResult
    func pruneHistory(
        maxCount: Int,
        maxTotalTextBytes: Int,
        removingItemsOlderThan cutoffDate: Date?
    ) -> Set<UUID> {
        guard cutoffDate != nil || maxCount > 0 || maxTotalTextBytes > 0 else {
            return []
        }

        var retainedRecords = fetchPruningRecords()
        var removedIDs = Set<UUID>()

        if let cutoffDate {
            retainedRecords.removeAll { record in
                guard record.timestamp < cutoffDate else { return false }
                removedIDs.insert(record.id)
                return true
            }
        }

        if maxCount > 0, retainedRecords.count > maxCount {
            retainedRecords.dropFirst(maxCount).forEach { removedIDs.insert($0.id) }
            retainedRecords = Array(retainedRecords.prefix(maxCount))
        }

        if maxTotalTextBytes > 0 {
            let byteLimit = Int64(maxTotalTextBytes)
            var totalBytes = retainedRecords.reduce(Int64(0)) { partialResult, record in
                let (sum, overflow) = partialResult.addingReportingOverflow(record.payloadByteCount)
                return overflow ? Int64.max : sum
            }
            if totalBytes > byteLimit {
                for record in retainedRecords.reversed() {
                    removedIDs.insert(record.id)
                    totalBytes = max(0, totalBytes - record.payloadByteCount)
                    if totalBytes <= byteLimit { break }
                }
            }
        }

        guard !removedIDs.isEmpty else { return [] }
        deleteEntries(withIDs: removedIDs)
        return removedIDs
    }

    // MARK: - Lightweight reads

    func fetchSnapshot(limit: Int = 0) -> ClipboardHistorySnapshot {
        #if DEBUG
        snapshotFetchCount += 1
        #endif
        return ClipboardHistorySnapshot(items: fetchSummaries(limit: limit))
    }

    func searchUnpinned(query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return fetchSnapshot().unpinnedItems }
        return fetchSummaries(predicate: NSPredicate(
            format: "isPinned == NO AND (text CONTAINS[cd] %@ OR fileURLsJSON CONTAINS[cd] %@)",
            query,
            query
        ))
    }

    func searchPinned(query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return fetchSnapshot().pinnedItems }
        let matches = fetchSummaries(predicate: NSPredicate(
            format: "isPinned == YES AND (favoriteKey CONTAINS[cd] %@ OR text CONTAINS[cd] %@ OR fileURLsJSON CONTAINS[cd] %@)",
            query,
            query,
            query
        ))
        return prioritizeFavoriteKeyMatches(matches, query: query)
    }

    func search(query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return fetchSnapshot().items }
        let matches = fetchSummaries(predicate: NSPredicate(
            format: "(isPinned == YES AND favoriteKey CONTAINS[cd] %@) OR text CONTAINS[cd] %@ OR fileURLsJSON CONTAINS[cd] %@",
            query,
            query,
            query
        ))
        return prioritizeFavoriteKeyMatches(matches, query: query)
    }

    // MARK: - Full payload reads

    func fetchAll(limit: Int = 0) -> [ClipboardItem] {
        fetchFullItems(limit: limit)
    }

    func fetchUnpinned() -> [ClipboardItem] {
        fetchFullItems(predicate: NSPredicate(format: "isPinned == NO"))
    }

    func fetchPinned() -> [ClipboardItem] {
        fetchFullItems(predicate: NSPredicate(format: "isPinned == YES"))
    }

    func fetch(id: UUID) -> ClipboardItem? {
        fetchFullItems(
            predicate: NSPredicate(format: "id == %@", id as CVarArg),
            limit: 1
        ).first
    }

    var count: Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
        return (try? context.count(for: request)) ?? 0
    }

    /// Migrated databases lack thumbnail and byte-count metadata. Process a small batch on a
    /// private context so launch and clipboard handling never load the old binary archive at once.
    func prepareLegacyMetadataBatch(
        limit: Int = 8,
        completion: @escaping (
            _ processedEntries: Bool,
            _ summariesChanged: Bool,
            _ mayHaveMore: Bool
        ) -> Void
    ) {
        let batchLimit = max(1, limit)
        container.performBackgroundTask { backgroundContext in
            backgroundContext.undoManager = nil
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "metadataPrepared == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            request.fetchLimit = batchLimit + 1
            request.fetchBatchSize = 1

            let fetchedEntries = (try? backgroundContext.fetch(request)) ?? []
            let entries = Array(fetchedEntries.prefix(batchLimit))
            var summariesChanged = false
            for entry in entries {
                autoreleasepool {
                    summariesChanged = Self.prepareMetadata(for: entry) || summariesChanged
                }
            }
            if backgroundContext.hasChanges {
                try? backgroundContext.save()
            }
            backgroundContext.reset()

            let processedEntries = !entries.isEmpty
            let mayHaveMore = fetchedEntries.count > batchLimit
            DispatchQueue.main.async {
                completion(processedEntries, summariesChanged, mayHaveMore)
            }
        }
    }

    // MARK: - Private

    private func prioritizeFavoriteKeyMatches(_ matches: [ClipboardItem], query: String) -> [ClipboardItem] {
        var keyMatches: [ClipboardItem] = []
        var valueMatches: [ClipboardItem] = []
        for item in matches {
            if item.isPinned,
               item.favoriteKey?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                keyMatches.append(item)
            } else {
                valueMatches.append(item)
            }
        }
        return keyMatches + valueMatches
    }

    private func fetchSummaries(
        predicate: NSPredicate? = nil,
        limit: Int = 0
    ) -> [ClipboardItem] {
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [
            "id",
            "timestamp",
            "isPinned",
            "favoriteKey",
            "text",
            "imageThumbnailData",
            "imagePixelWidth",
            "imagePixelHeight",
            "fileURLsJSON",
        ]
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        if limit > 0 { request.fetchLimit = limit }
        return (try? context.fetch(request))?.compactMap(mapSummary) ?? []
    }

    private func fetchFullItems(
        predicate: NSPredicate? = nil,
        limit: Int = 0
    ) -> [ClipboardItem] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchBatchSize = 32
        if limit > 0 { request.fetchLimit = limit }
        let items = (try? context.fetch(request))?.compactMap(mapFullItem) ?? []
        context.reset()
        return items
    }

    private func fetchPruningRecords() -> [PruningRecord] {
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "timestamp", "payloadByteCount"]
        request.predicate = NSPredicate(format: "isPinned == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return (try? context.fetch(request))?.compactMap { values in
            guard
                let id = uuid(from: values["id"]),
                let timestamp = values["timestamp"] as? Date
            else {
                return nil
            }
            let byteCount = (values["payloadByteCount"] as? NSNumber)?.int64Value ?? 0
            return PruningRecord(id: id, timestamp: timestamp, payloadByteCount: byteCount)
        } ?? []
    }

    private func fetchEntry(by id: UUID) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private func deleteUnpinnedEntries(matchingContentOf item: ClipboardItem) -> Set<UUID> {
        let predicate: NSPredicate
        switch item.content {
        case .text(let text):
            predicate = NSPredicate(format: "isPinned == NO AND text == %@", text)
        case .fileURLs(let urls):
            guard let json = fileURLsJSONString(for: urls) else { return [] }
            predicate = NSPredicate(format: "isPinned == NO AND fileURLsJSON == %@", json)
        case .image:
            return []
        }
        return deleteEntries(matching: predicate, saveImmediately: false)
    }

    @discardableResult
    private func deleteEntries(
        matching predicate: NSPredicate,
        saveImmediately: Bool = true
    ) -> Set<UUID> {
        let ids = matchingEntryIDs(predicate: predicate)
        guard !ids.isEmpty else { return [] }
        deleteEntries(withIDs: ids, saveImmediately: saveImmediately)
        return ids
    }

    private func matchingEntryIDs(predicate: NSPredicate) -> Set<UUID> {
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        request.predicate = predicate
        let values = (try? context.fetch(request)) ?? []
        return Set(values.compactMap { uuid(from: $0["id"]) })
    }

    private func deleteEntries<S: Sequence>(
        withIDs ids: S,
        saveImmediately: Bool = true
    ) where S.Element == UUID {
        let idArray = Array(ids)
        guard !idArray.isEmpty else { return }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: Self.entityName)
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "id IN %@", idArray)
        let objectIDs = (try? context.fetch(request)) ?? []
        objectIDs.forEach { context.delete(context.object(with: $0)) }
        if saveImmediately { saveContext() }
    }

    private func fileURLsJSONString(for urls: [URL]) -> String? {
        let strings = urls.map(\.absoluteString)
        guard let json = try? JSONEncoder().encode(strings) else { return nil }
        return String(data: json, encoding: .utf8)
    }

    private func mapSummary(_ values: NSDictionary) -> ClipboardItem? {
        guard
            let id = uuid(from: values["id"]),
            let timestamp = values["timestamp"] as? Date
        else {
            return nil
        }
        let isPinned = (values["isPinned"] as? NSNumber)?.boolValue ?? false
        let favoriteKey = values["favoriteKey"] as? String

        if let text = values["text"] as? String {
            return ClipboardItem(
                id: id,
                timestamp: timestamp,
                content: .text(text),
                isPinned: isPinned,
                favoriteKey: favoriteKey,
                payloadAvailability: .summary
            )
        }

        if let json = values["fileURLsJSON"] as? String,
           let urls = fileURLs(from: json), !urls.isEmpty {
            return ClipboardItem(
                id: id,
                timestamp: timestamp,
                content: .fileURLs(urls),
                isPinned: isPinned,
                favoriteKey: favoriteKey
            )
        }

        let thumbnailData = values["imageThumbnailData"] as? Data ?? Data()
        return ClipboardItem(
            id: id,
            timestamp: timestamp,
            content: .image(thumbnailData),
            isPinned: isPinned,
            favoriteKey: favoriteKey,
            payloadAvailability: .summary,
            imagePixelSize: imagePixelSize(from: values)
        )
    }

    private func mapFullItem(_ entry: NSManagedObject) -> ClipboardItem? {
        guard
            let id = entry.value(forKey: "id") as? UUID,
            let timestamp = entry.value(forKey: "timestamp") as? Date
        else {
            return nil
        }
        let isPinned = entry.value(forKey: "isPinned") as? Bool ?? false
        let favoriteKey = entry.value(forKey: "favoriteKey") as? String

        if let text = entry.value(forKey: "text") as? String {
            var richData: [String: Data]?
            if let blob = entry.value(forKey: "richDataBlob") as? Data,
               let dictionary = try? PropertyListSerialization.propertyList(
                   from: blob,
                   options: [],
                   format: nil
               ) as? [String: Data],
               !dictionary.isEmpty {
                richData = dictionary
            }
            return ClipboardItem(
                id: id,
                timestamp: timestamp,
                content: .text(text),
                isPinned: isPinned,
                favoriteKey: favoriteKey,
                richData: richData
            )
        }

        if let imageData = entry.value(forKey: "imageData") as? Data {
            return ClipboardItem(
                id: id,
                timestamp: timestamp,
                content: .image(imageData),
                isPinned: isPinned,
                favoriteKey: favoriteKey,
                imagePixelSize: imagePixelSize(from: entry)
            )
        }

        if let json = entry.value(forKey: "fileURLsJSON") as? String,
           let urls = fileURLs(from: json), !urls.isEmpty {
            return ClipboardItem(
                id: id,
                timestamp: timestamp,
                content: .fileURLs(urls),
                isPinned: isPinned,
                favoriteKey: favoriteKey
            )
        }

        return nil
    }

    private func fileURLs(from json: String) -> [URL]? {
        guard
            let data = json.data(using: .utf8),
            let strings = try? JSONDecoder().decode([String].self, from: data)
        else {
            return nil
        }
        return strings.compactMap(URL.init(string:))
    }

    private func imagePixelSize(from values: NSDictionary) -> CGSize? {
        guard
            let width = values["imagePixelWidth"] as? NSNumber,
            let height = values["imagePixelHeight"] as? NSNumber,
            width.doubleValue > 0,
            height.doubleValue > 0
        else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private func imagePixelSize(from entry: NSManagedObject) -> CGSize? {
        guard
            let width = entry.value(forKey: "imagePixelWidth") as? NSNumber,
            let height = entry.value(forKey: "imagePixelHeight") as? NSNumber,
            width.doubleValue > 0,
            height.doubleValue > 0
        else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private func uuid(from value: Any?) -> UUID? {
        if let uuid = value as? UUID { return uuid }
        return (value as? NSUUID).map { $0 as UUID }
    }

    @discardableResult
    private func saveContext() -> Bool {
        guard context.hasChanges else { return true }
        defer { context.reset() }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            print("FreePaste: Core Data 保存失败：\(error)")
            return false
        }
    }

    @discardableResult
    private static func prepareMetadata(for entry: NSManagedObject) -> Bool {
        let payloadByteCount: Int
        var summaryChanged = false
        if let text = entry.value(forKey: "text") as? String {
            let richBlob = entry.value(forKey: "richDataBlob") as? Data
            payloadByteCount = text.lengthOfBytes(using: .utf8) + (richBlob?.count ?? 0)
        } else if let imageData = entry.value(forKey: "imageData") as? Data {
            payloadByteCount = imageData.count
            if entry.value(forKey: "imageThumbnailData") == nil,
               let preview = ClipboardImageThumbnail.makePreview(from: imageData) {
                entry.setValue(preview.data, forKey: "imageThumbnailData")
                entry.setValue(preview.originalPixelSize.width, forKey: "imagePixelWidth")
                entry.setValue(preview.originalPixelSize.height, forKey: "imagePixelHeight")
                summaryChanged = true
            }
        } else if let json = entry.value(forKey: "fileURLsJSON") as? String {
            payloadByteCount = json.lengthOfBytes(using: .utf8)
        } else {
            payloadByteCount = 0
        }
        entry.setValue(Int64(payloadByteCount), forKey: "payloadByteCount")
        entry.setValue(true, forKey: "metadataPrepared")
        return summaryChanged
    }

    /// Programmatic models cannot be discovered in a .momd bundle during automatic migration.
    private static func migrateExistingStoreIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil
        )
        guard !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }

        let previousModel = model.copy() as! NSManagedObjectModel
        let previousEntity = previousModel.entitiesByName[entityName]!
        previousEntity.properties.removeAll { $0.name == "favoriteKey" }

        let legacyModel = previousModel.copy() as! NSManagedObjectModel
        let legacyEntity = legacyModel.entitiesByName[entityName]!
        let metadataFields: Set<String> = [
            "imageThumbnailData", "imagePixelWidth", "imagePixelHeight", "payloadByteCount", "metadataPrepared",
        ]
        legacyEntity.properties.removeAll { metadataFields.contains($0.name) }
        legacyEntity.indexes = []
        legacyEntity.attributesByName["imageData"]?.allowsExternalBinaryDataStorage = false
        legacyEntity.attributesByName["richDataBlob"]?.allowsExternalBinaryDataStorage = false

        guard let sourceModel = [previousModel, legacyModel].first(where: {
            $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        }) else { return }

        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: sourceModel, destinationModel: model
        )
        let migrationDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".FreePasteMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: migrationDirectory) }
        let migratedURL = migrationDirectory.appendingPathComponent("FreePaste.sqlite")
        let manager = NSMigrationManager(sourceModel: sourceModel, destinationModel: model)
        try manager.migrateStore(
            from: url, sourceType: NSSQLiteStoreType, options: nil, with: mapping,
            toDestinationURL: migratedURL, destinationType: NSSQLiteStoreType, destinationOptions: nil
        )
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.replacePersistentStore(
            at: url, destinationOptions: nil, withPersistentStoreFrom: migratedURL,
            sourceOptions: nil, ofType: NSSQLiteStoreType
        )
    }

    private func importLegacyHistoryIfNeeded(from sourceURL: URL) throws {
        guard let destinationURL = persistentStoreURL,
              container.persistentStoreCoordinator.persistentStores.first?.type == NSSQLiteStoreType,
              sourceURL.resolvingSymlinksInPath() != destinationURL.resolvingSymlinksInPath()
        else { return }
        let fileManager = FileManager.default
        let markerURL = destinationURL.appendingPathExtension("legacy-imported")
        guard !fileManager.fileExists(atPath: markerURL.path),
              fileManager.fileExists(atPath: sourceURL.path) else { return }

        let stagingDirectory = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".FreePasteLegacyImport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        let stagingURL = stagingDirectory.appendingPathComponent("FreePaste.sqlite")

        // Core Data copies the WAL and external payloads consistently; never migrate the original in place.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
        try coordinator.replacePersistentStore(
            at: stagingURL, destinationOptions: nil, withPersistentStoreFrom: sourceURL,
            sourceOptions: [NSReadOnlyPersistentStoreOption: true], ofType: NSSQLiteStoreType
        )
        let legacyStore = ClipboardHistoryStore(storeURL: stagingURL)
        guard legacyStore.container.persistentStoreCoordinator.persistentStores.first?.type == NSSQLiteStoreType
        else { throw CocoaError(.fileReadCorruptFile) }

        let legacyItems = legacyStore.fetchSnapshot().items
        guard !legacyItems.isEmpty else { return }
        let existingIDs = Set(fetchSnapshot().items.map(\.id))
        for summary in legacyItems where !existingIDs.contains(summary.id) {
            try autoreleasepool {
                guard let item = legacyStore.fetch(id: summary.id) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                add(item, deduplicate: false)
                guard fetch(id: item.id) != nil else { throw CocoaError(.fileWriteUnknown) }
            }
        }
        try Data().write(to: markerURL, options: .atomic)
    }

    private static func legacyPersistentStoreURL() -> URL? {
        // Foundation's home-directory helpers can resolve to the container, even for the current username.
        guard let homePath = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let home = String(cString: homePath)
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/FreePaste/FreePaste.sqlite")
    }

    static func defaultPersistentStoreURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("FreePaste", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("FreePaste.sqlite")
    }
}
