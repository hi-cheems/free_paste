//
//  ClipboardMonitor.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/12.
//

import AppKit
import Combine
import Foundation

/// 对 NSPasteboard 的最小抽象，使监听器可被测试
protocol PasteboardReading {
    var changeCount: Int { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    func readFileURLs() -> [URL]
}

extension NSPasteboard: PasteboardReading {
    func readFileURLs() -> [URL] {
        (readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
    }
}

/// 监听系统剪切板变化，通过 Combine Publisher 对外发布新条目
final class ClipboardMonitor: ObservableObject {

    /// 每当剪切板出现新内容时发布一个 ClipboardItem
    let newItem = PassthroughSubject<ClipboardItem, Never>()

    private let pasteboard: PasteboardReading
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int

    /// - Parameters:
    ///   - pasteboard: 剪切板数据源，默认使用系统剪切板
    ///   - interval: 轮询间隔（秒），默认 0.5s
    init(pasteboard: PasteboardReading = NSPasteboard.general, interval: TimeInterval = 0.5) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount
    }

    /// 开始监听，重复调用无效
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// 停止监听
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 将 lastChangeCount 同步到剪贴板当前值，使下一次轮询跳过本次变更。
    /// 用于 App 自身写入剪贴板后避免触发重复检测。
    @discardableResult
    func syncChangeCount() -> Bool {
        let hadUnobservedChange = lastChangeCount != pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
        return hadUnobservedChange
    }

    /// Reads the current clipboard immediately, without waiting for another change-count tick.
    func currentItem() -> ClipboardItem? {
        // 优先级：文件 URL > 图片 > 文本
        let fileURLs = pasteboard.readFileURLs()
        if !fileURLs.isEmpty {
            return ClipboardItem(content: .fileURLs(fileURLs))
        }

        if let tiffData = pasteboard.data(forType: .tiff) {
            return ClipboardItem(content: .image(tiffData))
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }
        var richData: [String: Data] = [:]
        for type in Self.richPasteboardTypes {
            if let data = pasteboard.data(forType: type) {
                richData[type.rawValue] = data
            }
        }
        return ClipboardItem(
            content: .text(text),
            richData: richData.isEmpty ? nil : richData
        )
    }

    // MARK: - Private

    private func poll() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if let item = currentItem() {
            newItem.send(item)
        }
    }

    /// 需要保留的富文本格式类型
    private static let richPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .rtf,
        .rtfd,
        NSPasteboard.PasteboardType("public.html"),
    ]
}
