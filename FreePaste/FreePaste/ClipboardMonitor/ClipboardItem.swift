//
//  ClipboardItem.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/12.
//

import Foundation

/// 剪切板内容类型
enum ClipboardContent: Equatable {
    case text(String)
    case image(Data)        // TIFF 图片数据
    case fileURLs([URL])    // 文件 URL 列表（Finder 复制）
}

/// Whether `content` contains the complete clipboard payload or a lightweight UI summary.
enum ClipboardPayloadAvailability: Equatable {
    case complete
    case summary
}

/// 一条剪切板历史记录
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let content: ClipboardContent
    var isPinned: Bool
    var favoriteKey: String?
    /// 富文本原始数据（仅 .text 条目可能持有），key 为 NSPasteboard.PasteboardType.rawValue
    var richData: [String: Data]?
    /// Summary records keep large image/rich-text payloads on disk until paste time.
    let payloadAvailability: ClipboardPayloadAvailability
    /// Original image dimensions, retained even when `content` only carries a thumbnail.
    let imagePixelSize: CGSize?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: ClipboardContent,
        isPinned: Bool = false,
        favoriteKey: String? = nil,
        richData: [String: Data]? = nil,
        payloadAvailability: ClipboardPayloadAvailability = .complete,
        imagePixelSize: CGSize? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.isPinned = isPinned
        self.favoriteKey = favoriteKey
        self.richData = richData
        self.payloadAvailability = payloadAvailability
        self.imagePixelSize = imagePixelSize
    }
}
