//
//  BatchPasteSessionTests.swift
//  FreePasteTests
//

import XCTest

@testable import FreePaste

final class BatchPasteSessionTests: XCTestCase {
    func test_start_seedsSessionWithInitialClipboardItem() {
        let session = BatchPasteSession(direction: .forward)
        let initialItem = item("clipboard")

        XCTAssertTrue(session.start(with: initialItem))

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.items.map(\.id), [initialItem.id])
    }

    func test_start_rejectsOversizedInitialItemWithoutActivatingSession() {
        let session = BatchPasteSession(maximumItemCount: 10, maximumByteCount: 2)

        XCTAssertFalse(session.start(with: item("too large")))

        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.items.isEmpty)
    }

    func test_dragReorder_keepsNewSlotUntilPointerCrossesReverseThreshold() {
        let movedDown = BatchPasteDragReorder.step(
            currentIndex: 1,
            anchorTranslation: 0,
            translation: 27,
            rowHeight: 44,
            itemCount: 4
        )

        XCTAssertEqual(movedDown, .init(index: 2, anchorTranslation: 44))

        let slightReverse = BatchPasteDragReorder.step(
            currentIndex: movedDown.index,
            anchorTranslation: movedDown.anchorTranslation,
            translation: 25,
            rowHeight: 44,
            itemCount: 4
        )

        XCTAssertEqual(slightReverse, movedDown)

        let crossedReverseThreshold = BatchPasteDragReorder.step(
            currentIndex: slightReverse.index,
            anchorTranslation: slightReverse.anchorTranslation,
            translation: 17,
            rowHeight: 44,
            itemCount: 4
        )

        XCTAssertEqual(crossedReverseThreshold, .init(index: 1, anchorTranslation: 0))
    }

    func test_dragReorder_crossesMultipleRowsAndClampsAtListBounds() {
        XCTAssertEqual(
            BatchPasteDragReorder.step(
                currentIndex: 0,
                anchorTranslation: 0,
                translation: 120,
                rowHeight: 44,
                itemCount: 4
            ),
            .init(index: 3, anchorTranslation: 132)
        )
        XCTAssertEqual(
            BatchPasteDragReorder.step(
                currentIndex: 1,
                anchorTranslation: 0,
                translation: -200,
                rowHeight: 44,
                itemCount: 4
            ),
            .init(index: 0, anchorTranslation: -44)
        )
    }

    func test_forwardCollection_appendsInCaptureOrder() {
        let session = BatchPasteSession(direction: .forward)
        session.start(with: item("A"))

        session.add(item("B"))
        session.add(item("A"))

        XCTAssertEqual(texts(in: session), ["A", "B", "A"])
    }

    func test_reverseCollection_placesNewestItemFirst() {
        let session = BatchPasteSession(direction: .reverse)
        session.start(with: item("A"))

        session.add(item("B"))
        session.add(item("C"))

        XCTAssertEqual(texts(in: session), ["C", "B", "A"])
    }

    func test_switchingDirection_reversesOnlyRemainingItems() {
        let session = BatchPasteSession(direction: .forward)
        session.start(with: item("A"))
        session.add(item("B"))
        session.add(item("C"))
        XCTAssertEqual(session.takeNext()?.content, .text("A"))

        session.setDirection(.reverse)

        XCTAssertEqual(texts(in: session), ["C", "B"])
    }

    func test_takeNext_prefersSelectionAndSelectsFollowingItem() {
        let session = BatchPasteSession()
        let a = item("A")
        let b = item("B")
        let c = item("C")
        session.start(with: a)
        [b, c].forEach { session.add($0) }
        session.selectedItemID = b.id

        XCTAssertEqual(session.takeNext()?.id, b.id)
        XCTAssertEqual(session.selectedItemID, c.id)
        XCTAssertEqual(texts(in: session), ["A", "C"])
    }

    func test_removingLastSelectedItem_selectsNewLastItem() {
        let session = BatchPasteSession()
        let a = item("A")
        let b = item("B")
        session.start(with: a)
        session.add(b)
        session.selectedItemID = b.id

        session.remove(id: b.id)

        XCTAssertEqual(session.selectedItemID, a.id)
    }

    func test_removingFinalItem_endsSession() {
        let session = BatchPasteSession()
        let only = item("only")
        session.start(with: only)

        session.remove(id: only.id)

        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.items.isEmpty)
    }

    func test_moveSelected_usesArrowDirectionAndKeepsSelection() {
        let session = BatchPasteSession()
        let a = item("A")
        let b = item("B")
        let c = item("C")
        session.start(with: a)
        [b, c].forEach { session.add($0) }
        session.selectedItemID = b.id

        session.moveSelected(by: -1)

        XCTAssertEqual(texts(in: session), ["B", "A", "C"])
        XCTAssertEqual(session.selectedItemID, b.id)
    }

    func test_dragMove_canMoveItemDownAndUp() {
        let session = BatchPasteSession()
        let a = item("A")
        let b = item("B")
        let c = item("C")
        session.start(with: a)
        [b, c].forEach { session.add($0) }

        session.move(id: a.id, to: 2)
        XCTAssertEqual(texts(in: session), ["B", "C", "A"])

        session.move(id: a.id, to: 0)
        XCTAssertEqual(texts(in: session), ["A", "B", "C"])
    }

    func test_capacityLimit_rejectsNewItemAndRecoversAfterRemoval() {
        let session = BatchPasteSession(maximumItemCount: 2, maximumByteCount: 100)
        let a = item("A")
        session.start(with: a)
        session.add(item("B"))

        XCTAssertFalse(session.add(item("C")))
        XCTAssertTrue(session.isCapacityWarningVisible)
        session.remove(id: a.id)
        XCTAssertFalse(session.isCapacityWarningVisible)
        XCTAssertTrue(session.add(item("C")))
        XCTAssertEqual(texts(in: session), ["B", "C"])
    }

    func test_byteLimit_includesRichTextPayload() {
        let session = BatchPasteSession(maximumItemCount: 10, maximumByteCount: 5)
        let richItem = ClipboardItem(
            content: .text("A"),
            richData: ["public.rtf": Data([1, 2, 3, 4, 5])]
        )

        XCTAssertFalse(session.start(with: richItem))
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.items.isEmpty)
    }

    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(content: .text(text))
    }

    private func texts(in session: BatchPasteSession) -> [String] {
        session.items.compactMap {
            guard case .text(let text) = $0.content else { return nil }
            return text
        }
    }
}
