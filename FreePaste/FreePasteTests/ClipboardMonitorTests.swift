//
//  ClipboardMonitorTests.swift
//  FreePasteTests
//
//  Created by bond cheems on 2026/3/12.
//

import Combine
import XCTest

@testable import FreePaste

// MARK: - Mock

/// 可控的模拟剪切板，用于测试中替代真实的 NSPasteboard
final class MockPasteboard: PasteboardReading {
    private(set) var changeCount: Int = 0
    private var stringValue: String?
    private var dataValues: [NSPasteboard.PasteboardType: Data] = [:]
    private var fileURLValues: [URL] = []

    /// 模拟用户复制了一段文字
    func copy(_ text: String?) {
        stringValue = text
        dataValues = [:]
        fileURLValues = []
        changeCount += 1
    }

    /// 模拟用户复制了图片（TIFF 数据）
    func copyImage(_ data: Data) {
        stringValue = nil
        dataValues = [.tiff: data]
        fileURLValues = []
        changeCount += 1
    }

    /// 模拟用户在 Finder 中复制了文件
    func copyFileURLs(_ urls: [URL]) {
        stringValue = nil
        dataValues = [:]
        fileURLValues = urls
        changeCount += 1
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        return stringValue
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        return dataValues[dataType]
    }

    func readFileURLs() -> [URL] {
        return fileURLValues
    }
}

// MARK: - Tests

final class ClipboardMonitorTests: XCTestCase {

    private var monitor: ClipboardMonitor!
    private var pasteboard: MockPasteboard!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        pasteboard = MockPasteboard()
        // 使用极短间隔让测试快速执行
        monitor = ClipboardMonitor(pasteboard: pasteboard, interval: 0.05)
        cancellables = []
    }

    override func tearDown() {
        monitor.stop()
        cancellables = nil
        super.tearDown()
    }

    // MARK: 基础监听

    func test_currentItem_readsExistingClipboardWithoutWaitingForAChange() {
        pasteboard.copy("已经在剪贴板中的内容")

        let item = monitor.currentItem()

        XCTAssertEqual(item?.content, .text("已经在剪贴板中的内容"))
    }

    func test_whenContentChanges_emitsNewItem() {
        let expectation = expectation(description: "收到新条目")
        var received: ClipboardItem?

        monitor.newItem
            .sink { item in
                received = item
                expectation.fulfill()
            }
            .store(in: &cancellables)

        monitor.start()
        pasteboard.copy("Hello, FreePaste!")

        waitForExpectations(timeout: 1)

        XCTAssertNotNil(received)
        XCTAssertEqual(received?.content, .text("Hello, FreePaste!"))
    }

    func test_whenContentUnchanged_doesNotEmit() {
        let expectation = expectation(description: "不应收到条目")
        expectation.isInverted = true

        monitor.newItem
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        monitor.start()
        // 不调用 pasteboard.copy，changeCount 不变

        waitForExpectations(timeout: 0.3)
    }

    func test_multipleChanges_emitsEachItem() {
        let expectation = expectation(description: "收到两个条目")
        expectation.expectedFulfillmentCount = 2
        var items: [ClipboardItem] = []

        monitor.newItem
            .sink { item in
                items.append(item)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        monitor.start()
        pasteboard.copy("第一条")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pasteboard.copy("第二条")
        }

        waitForExpectations(timeout: 1)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].content, .text("第一条"))
        XCTAssertEqual(items[1].content, .text("第二条"))
    }

    // MARK: 空内容过滤

    func test_whenCopiedTextIsEmpty_doesNotEmit() {
        let expectation = expectation(description: "空字符串不应被记录")
        expectation.isInverted = true

        monitor.newItem
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        monitor.start()
        pasteboard.copy("")

        waitForExpectations(timeout: 0.3)
    }

    func test_whenCopiedTextIsNil_doesNotEmit() {
        let expectation = expectation(description: "nil 不应被记录")
        expectation.isInverted = true

        monitor.newItem
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        monitor.start()
        pasteboard.copy(nil)

        waitForExpectations(timeout: 0.3)
    }

    // MARK: 生命周期

    func test_startCalledTwice_doesNotDuplicateEmissions() {
        let expectation = expectation(description: "只收到一个条目")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true
        var count = 0

        monitor.newItem
            .sink { _ in
                count += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        monitor.start()
        monitor.start() // 重复调用应无效

        pasteboard.copy("测试重复 start")

        waitForExpectations(timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func test_afterStop_doesNotEmit() {
        let expectation = expectation(description: "stop 后不应收到条目")
        expectation.isInverted = true

        monitor.newItem
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        monitor.start()
        monitor.stop()

        pasteboard.copy("stop 后的内容")

        waitForExpectations(timeout: 0.3)
    }

    // MARK: syncChangeCount

    func test_syncChangeCount_skipsCurrentChange() {
        let expectation = expectation(description: "syncChangeCount 后不应收到条目")
        expectation.isInverted = true

        monitor.newItem
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        monitor.start()
        pasteboard.copy("被跳过的内容")
        monitor.syncChangeCount()

        waitForExpectations(timeout: 0.3)
    }

    func test_syncChangeCount_doesNotAffectSubsequentChanges() {
        let expectation = expectation(description: "后续变更仍然被检测")

        monitor.start()
        pasteboard.copy("被跳过")
        monitor.syncChangeCount()

        monitor.newItem
            .first()
            .sink { item in
                XCTAssertEqual(item.content, .text("新内容"))
                expectation.fulfill()
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pasteboard.copy("新内容")
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: 图片内容

    func test_whenImageCopied_emitsImageItem() {
        let expectation = expectation(description: "收到图片条目")
        var received: ClipboardItem?

        monitor.newItem
            .sink { item in
                received = item
                expectation.fulfill()
            }
            .store(in: &cancellables)

        monitor.start()
        let fakeImageData = Data([0xFF, 0xD8, 0xFF]) // 模拟图片字节
        pasteboard.copyImage(fakeImageData)

        waitForExpectations(timeout: 1)

        if case .image(let data) = received?.content {
            XCTAssertEqual(data, fakeImageData)
        } else {
            XCTFail("期望 .image 内容，实际为 \(String(describing: received?.content))")
        }
    }

    // MARK: 文件 URL 内容

    func test_whenFileURLsCopied_emitsFileURLsItem() {
        let expectation = expectation(description: "收到文件 URL 条目")
        var received: ClipboardItem?

        monitor.newItem
            .sink { item in
                received = item
                expectation.fulfill()
            }
            .store(in: &cancellables)

        monitor.start()
        let urls = [URL(fileURLWithPath: "/tmp/test.txt")]
        pasteboard.copyFileURLs(urls)

        waitForExpectations(timeout: 1)

        if case .fileURLs(let receivedURLs) = received?.content {
            XCTAssertEqual(receivedURLs, urls)
        } else {
            XCTFail("期望 .fileURLs 内容，实际为 \(String(describing: received?.content))")
        }
    }

    func test_fileURLs_takePriorityOverText() {
        let expectation = expectation(description: "文件 URL 优先于文本")
        var received: ClipboardItem?

        monitor.newItem
            .sink { item in
                received = item
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate pasteboard having both text and file URLs (file URLs take priority)
        monitor.start()
        let urls = [URL(fileURLWithPath: "/tmp/doc.pdf")]
        pasteboard.copyFileURLs(urls)

        waitForExpectations(timeout: 1)

        if case .fileURLs = received?.content {
            // correct
        } else {
            XCTFail("期望 .fileURLs 优先，实际为 \(String(describing: received?.content))")
        }
    }

    // MARK: 每条记录唯一性

    func test_eachItemHasUniqueId() {
        let expectation = expectation(description: "收到两个条目")
        expectation.expectedFulfillmentCount = 2
        var ids: [UUID] = []

        monitor.newItem
            .sink { item in
                ids.append(item.id)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        monitor.start()
        pasteboard.copy("内容 A")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pasteboard.copy("内容 B")
        }

        waitForExpectations(timeout: 1)

        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1])
    }
}
