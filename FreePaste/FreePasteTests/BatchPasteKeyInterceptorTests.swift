//
//  BatchPasteKeyInterceptorTests.swift
//  FreePasteTests
//

import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import FreePaste

final class BatchPasteKeyInterceptorTests: XCTestCase {
    func test_exactCommandV_isIntercepted() {
        XCTAssertEqual(
            BatchPasteKeyInterceptor.decision(
                keyCode: Int64(kVK_ANSI_V),
                flags: .maskCommand,
                isAutoRepeat: false,
                sourceUserData: 0
            ),
            .triggerPaste
        )
    }

    func test_alternatePasteShortcut_isNotIntercepted() {
        XCTAssertEqual(
            BatchPasteKeyInterceptor.decision(
                keyCode: Int64(kVK_ANSI_V),
                flags: [.maskCommand, .maskShift],
                isAutoRepeat: false,
                sourceUserData: 0
            ),
            .passThrough
        )
    }

    func test_autoRepeat_isSuppressedWithoutConsumingAnotherItem() {
        XCTAssertEqual(
            BatchPasteKeyInterceptor.decision(
                keyCode: Int64(kVK_ANSI_V),
                flags: .maskCommand,
                isAutoRepeat: true,
                sourceUserData: 0
            ),
            .suppress
        )
    }

    func test_syntheticPasteEvent_isAllowedThrough() {
        XCTAssertEqual(
            BatchPasteKeyInterceptor.decision(
                keyCode: Int64(kVK_ANSI_V),
                flags: .maskCommand,
                isAutoRepeat: false,
                sourceUserData: FreePasteSyntheticEvent.marker
            ),
            .passThrough
        )
    }

    func test_otherCommandKey_isNotIntercepted() {
        XCTAssertEqual(
            BatchPasteKeyInterceptor.decision(
                keyCode: Int64(kVK_ANSI_C),
                flags: .maskCommand,
                isAutoRepeat: false,
                sourceUserData: 0
            ),
            .passThrough
        )
    }

    func test_selectionCapture_waitsForAClipboardChangeAfterSendingCopy() {
        let pasteboard = MockSelectionPasteboard()
        pasteboard.copy("old clipboard")
        let sender = MockCopyShortcutSender()
        var scheduledPoll: (() -> Void)?
        let capture = BatchPasteSelectionCaptureService(
            pasteboard: pasteboard,
            shortcutSender: sender,
            maximumPollAttempts: 2,
            scheduler: { _, action in scheduledPoll = action }
        )
        var result: Bool?

        capture.captureSelection { result = $0 }

        XCTAssertEqual(sender.sendCount, 1)
        XCTAssertNil(result)

        pasteboard.copy("current selection")
        scheduledPoll?()

        XCTAssertEqual(result, true)
        XCTAssertEqual(pasteboard.currentText, "current selection")
    }

    func test_selectionCapture_doesNotAcceptUnchangedClipboardContent() {
        let pasteboard = MockSelectionPasteboard()
        pasteboard.copy("stale clipboard")
        let sender = MockCopyShortcutSender()
        var scheduledPolls: [() -> Void] = []
        let capture = BatchPasteSelectionCaptureService(
            pasteboard: pasteboard,
            shortcutSender: sender,
            maximumPollAttempts: 2,
            scheduler: { _, action in scheduledPolls.append(action) }
        )
        var result: Bool?

        capture.captureSelection { result = $0 }
        while !scheduledPolls.isEmpty {
            let poll = scheduledPolls.removeFirst()
            poll()
        }

        XCTAssertEqual(result, false)
    }

    func test_selectionCapture_failsImmediatelyWhenCopyCannotBeSent() {
        let pasteboard = MockSelectionPasteboard()
        let sender = MockCopyShortcutSender(sendResult: false)
        var didSchedulePoll = false
        let capture = BatchPasteSelectionCaptureService(
            pasteboard: pasteboard,
            shortcutSender: sender,
            scheduler: { _, _ in didSchedulePoll = true }
        )
        var result: Bool?

        capture.captureSelection { result = $0 }

        XCTAssertEqual(result, false)
        XCTAssertFalse(didSchedulePoll)
    }
}

private final class MockCopyShortcutSender: CopyShortcutSending {
    private let sendResult: Bool
    private(set) var sendCount = 0

    init(sendResult: Bool = true) {
        self.sendResult = sendResult
    }

    func sendCopyShortcut() -> Bool {
        sendCount += 1
        return sendResult
    }
}

private final class MockSelectionPasteboard: PasteboardChangeCountReading {
    private(set) var changeCount = 0
    private(set) var currentText: String?

    func copy(_ text: String) {
        currentText = text
        changeCount += 1
    }
}
