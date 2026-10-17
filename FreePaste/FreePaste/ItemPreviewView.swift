//
//  ItemPreviewView.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import SwiftUI

struct TextPreviewConfiguration: Equatable {
    static let selectionLimit = 800
    static let truncationTrigger = 1_200
    static let truncatedLength = 800

    let displayedText: String
    let allowsSelection: Bool
    let notice: String?

    init(text: String) {
        if text.count > Self.truncationTrigger {
            displayedText = String(text.prefix(Self.truncatedLength))
            allowsSelection = false
            notice = "内容过长，仅预览前 \(Self.truncatedLength.formatted()) 个字符。"
        } else if text.count > Self.selectionLimit {
            displayedText = text
            allowsSelection = false
            notice = "内容较长，已关闭文本选择以提升预览性能。"
        } else {
            displayedText = text
            allowsSelection = true
            notice = nil
        }
    }
}

struct ItemPreviewView: View {
    private static let fileURLPreviewLimit = 20

    let item: ClipboardItem

    private var textPreviewConfiguration: TextPreviewConfiguration? {
        guard case .text(let text) = item.content else { return nil }
        return TextPreviewConfiguration(text: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Group {
                    switch item.content {
                    case .text:
                        if let textPreviewConfiguration {
                            previewTextView(configuration: textPreviewConfiguration)
                        }

                    case .image(let data):
                        if let nsImage = ClipboardThumbnailCache.shared.image(for: item.id, data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }

                    case .fileURLs(let urls):
                        previewFileURLsView(urls: urls)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textMuted)
                Text(item.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("随选中项自动预览")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            LinearGradient(
                colors: [AppTheme.panelTop, AppTheme.surfaceElevated],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .tint(AppTheme.accent)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func previewTextView(configuration: TextPreviewConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = configuration.notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                    Text(notice)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.warningSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.warning.opacity(0.2), lineWidth: 1)
                )
            }

            if configuration.allowsSelection {
                Text(configuration.displayedText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(configuration.displayedText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func previewFileURLsView(urls: [URL]) -> some View {
        let displayedURLs = Array(urls.prefix(Self.fileURLPreviewLimit))
        return VStack(alignment: .leading, spacing: 8) {
            if urls.count > displayedURLs.count {
                previewNotice("文件较多，仅预览前 \(Self.fileURLPreviewLimit) 个。")
            }

            ForEach(displayedURLs, id: \.self) { url in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(url.path)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewNotice(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
            Text(notice)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.warningSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.warning.opacity(0.2), lineWidth: 1)
        )
    }
}
