//
//  BatchPasteSession.swift
//  FreePaste
//

import Combine
import Foundation

enum BatchPasteDirection: String, Codable, CaseIterable, Identifiable {
    case forward
    case reverse

    var id: Self { self }

    var title: String {
        switch self {
        case .forward: return "正序"
        case .reverse: return "倒序"
        }
    }
}

/// Owns the ephemeral batch queue. `items[0]` is always the default next output.
final class BatchPasteSession: ObservableObject {
    static let defaultMaximumItemCount = 200
    static let defaultMaximumByteCount = 256 * 1_048_576

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isActive = false
    @Published private(set) var direction: BatchPasteDirection
    @Published var selectedItemID: ClipboardItem.ID?
    @Published private(set) var isCapacityWarningVisible = false

    private let maximumItemCount: Int
    private let maximumByteCount: Int
    private var totalByteCount = 0

    init(
        direction: BatchPasteDirection = .forward,
        maximumItemCount: Int = BatchPasteSession.defaultMaximumItemCount,
        maximumByteCount: Int = BatchPasteSession.defaultMaximumByteCount
    ) {
        self.direction = direction
        self.maximumItemCount = maximumItemCount
        self.maximumByteCount = maximumByteCount
    }

    @discardableResult
    func start(
        with initialItem: ClipboardItem,
        direction: BatchPasteDirection? = nil
    ) -> Bool {
        items.removeAll()
        totalByteCount = 0
        selectedItemID = nil
        isCapacityWarningVisible = false
        if let direction {
            self.direction = direction
        }

        let byteCount = Self.estimatedByteCount(of: initialItem)
        guard maximumItemCount > 0, byteCount <= maximumByteCount else {
            isActive = false
            isCapacityWarningVisible = true
            return false
        }

        items = [initialItem]
        totalByteCount = byteCount
        isActive = true
        return true
    }

    func finish() {
        items.removeAll()
        totalByteCount = 0
        selectedItemID = nil
        isCapacityWarningVisible = false
        isActive = false
    }

    @discardableResult
    func add(_ item: ClipboardItem) -> Bool {
        guard isActive else { return false }
        let byteCount = Self.estimatedByteCount(of: item)
        guard items.count < maximumItemCount,
              byteCount <= maximumByteCount - totalByteCount
        else {
            isCapacityWarningVisible = true
            return false
        }

        switch direction {
        case .forward:
            items.append(item)
        case .reverse:
            items.insert(item, at: 0)
        }
        totalByteCount += byteCount
        isCapacityWarningVisible = false
        return true
    }

    func setDirection(_ newDirection: BatchPasteDirection) {
        guard direction != newDirection else { return }
        direction = newDirection
        items.reverse()
    }

    /// Removes and returns the selected item, or the first item when nothing is selected.
    func takeNext() -> ClipboardItem? {
        let id = selectedItemID ?? items.first?.id
        guard let id else { return nil }
        return remove(id: id)
    }

    @discardableResult
    func remove(id: ClipboardItem.ID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = items.remove(at: index)
        totalByteCount -= Self.estimatedByteCount(of: removed)
        isCapacityWarningVisible = false

        if items.isEmpty {
            selectedItemID = nil
            isActive = false
        } else if selectedItemID == id {
            selectedItemID = items[min(index, items.count - 1)].id
        }
        return removed
    }

    func moveSelected(by offset: Int) {
        guard offset != 0,
              let selectedItemID,
              let sourceIndex = items.firstIndex(where: { $0.id == selectedItemID })
        else {
            if self.selectedItemID == nil {
                self.selectedItemID = items.first?.id
            }
            return
        }

        let destinationIndex = min(max(0, sourceIndex + offset), items.count - 1)
        guard sourceIndex != destinationIndex else { return }
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: destinationIndex)
    }

    func move(id: ClipboardItem.ID, to destinationIndex: Int) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let clampedDestination = min(max(0, destinationIndex), items.count - 1)
        guard sourceIndex != clampedDestination else { return }

        let item = items.remove(at: sourceIndex)
        items.insert(item, at: clampedDestination)
    }

    func clearSelection() {
        selectedItemID = nil
    }

    static func estimatedByteCount(of item: ClipboardItem) -> Int {
        let contentByteCount: Int
        switch item.content {
        case .text(let text):
            contentByteCount = text.lengthOfBytes(using: .utf8)
        case .image(let data):
            contentByteCount = data.count
        case .fileURLs(let urls):
            contentByteCount = urls.reduce(0) {
                $0 + $1.absoluteString.lengthOfBytes(using: .utf8)
            }
        }
        let richTextByteCount = item.richData?.values.reduce(0) { $0 + $1.count } ?? 0
        return contentByteCount + richTextByteCount
    }
}
