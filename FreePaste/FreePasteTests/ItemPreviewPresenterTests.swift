//
//  ItemPreviewPresenterTests.swift
//  FreePasteTests
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import XCTest

@testable import FreePaste

final class ItemPreviewPresenterTests: XCTestCase {

    func test_makePanel_keepsPopoverEligibleForKeyboardFocus() {
        let panel = ItemPreviewPresenter.makePanel(
            contentViewController: NSViewController()
        )

        XCTAssertEqual(panel.title, "全文预览")
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.closable))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
    }

    func test_textPreviewConfiguration_keepsShortTextSelectable() {
        let configuration = TextPreviewConfiguration(text: "short text")

        XCTAssertEqual(configuration.displayedText, "short text")
        XCTAssertTrue(configuration.allowsSelection)
        XCTAssertNil(configuration.notice)
    }

    func test_textPreviewConfiguration_disablesSelectionForLongText() {
        let text = String(repeating: "a", count: TextPreviewConfiguration.selectionLimit + 1)
        let configuration = TextPreviewConfiguration(text: text)

        XCTAssertEqual(configuration.displayedText.count, text.count)
        XCTAssertFalse(configuration.allowsSelection)
        XCTAssertEqual(configuration.notice, "内容较长，已关闭文本选择以提升预览性能。")
    }

    func test_textPreviewConfiguration_truncatesVeryLongText() {
        let text = String(repeating: "b", count: TextPreviewConfiguration.truncationTrigger + 1)
        let configuration = TextPreviewConfiguration(text: text)

        XCTAssertEqual(configuration.displayedText.count, TextPreviewConfiguration.truncatedLength)
        XCTAssertFalse(configuration.allowsSelection)
        XCTAssertEqual(
            configuration.notice,
            "内容过长，仅预览前 \(TextPreviewConfiguration.truncatedLength.formatted()) 个字符。"
        )
    }
}
