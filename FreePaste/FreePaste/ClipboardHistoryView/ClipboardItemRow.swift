//
//  ClipboardItemRow.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/13.
//

import SwiftUI

struct ClipboardItemRow: View {
    @EnvironmentObject private var manager: ClipboardManager
    let item: ClipboardItem
    let isSelected: Bool
    let cardHeight: CGFloat
    let onSelect: () -> Void
    let onConfirm: () -> Void
    let onTogglePin: () -> Void
    let onPlainTextPaste: (() -> Void)?
    var onEditFavoriteKey: (() -> Void)? = nil
    var onPreview: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            cardBody
            cardFooter
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder)
        .shadow(
            color: isSelected ? AppTheme.selection.opacity(0.2) : .black.opacity(isHovering ? 0.12 : 0.07),
            radius: isSelected ? 10 : 7,
            x: 0,
            y: 4
        )
        .scaleEffect(isSelected ? 1 : (isHovering ? 1.01 : 1))
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .contentShape(Rectangle())
        .highPriorityGesture(doubleClickConfirmGesture)
        .simultaneousGesture(singleClickSelectGesture)
        .onHover { isHovering = $0 }
        .contextMenu {
            if let onPreview {
                Button("预览", systemImage: "eye", action: onPreview)
            }
            if item.isPinned, let onEditFavoriteKey {
                Button("设置 Key", systemImage: "tag", action: onEditFavoriteKey)
            }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: contentIconName)
                .font(.system(size: 11, weight: .bold))
            Text(contentTypeTitle)
                .font(.system(size: 12, weight: .bold))
            Spacer(minLength: 4)
            Text(shortTimestamp)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(contentHeaderColor)
    }

    @ViewBuilder
    private var cardBody: some View {
        switch item.content {
        case .text(let text):
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(maxTextLines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(bodyPadding)

        case .image(let data):
            if let nsImage = ClipboardThumbnailCache.shared.image(for: item.id, data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                unavailableBody(iconName: "photo", title: "无法读取图片")
            }

        case .fileURLs(let urls):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(urls.prefix(visibleFileCount)), id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if urls.count > visibleFileCount {
                    Text("另有 \(urls.count - visibleFileCount) 个文件")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(bodyPadding)
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            Text(item.isPinned ? (item.favoriteKey ?? contentDetail) : contentDetail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
                .help(item.isPinned ? (item.favoriteKey ?? contentDetail) : contentDetail)
            Spacer(minLength: 4)
            actionButtons
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(AppTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.lineSoft)
                .frame(height: 1)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 3) {
            if case .text = item.content, let onPlainTextPaste {
                cardActionButton(
                    iconName: "textformat",
                    help: "粘贴为纯文本",
                    action: onPlainTextPaste
                )
            }

            cardActionButton(
                iconName: item.isPinned ? "star.fill" : "star",
                color: item.isPinned ? AppTheme.favorite : AppTheme.textMuted,
                help: item.isPinned ? "取消收藏" : "收藏",
                action: onTogglePin
            )

            cardActionButton(
                iconName: "trash",
                color: AppTheme.danger,
                help: "删除"
            ) {
                manager.delete(item)
            }
        }
        .opacity(isHovering || isSelected || item.isPinned ? 1 : 0)
    }

    private func cardActionButton(
        iconName: String,
        color: Color = AppTheme.textMuted,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var singleClickSelectGesture: some Gesture {
        TapGesture(count: 1)
            .onEnded { onSelect() }
    }

    private var doubleClickConfirmGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                onSelect()
                onConfirm()
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
                isSelected ? AppTheme.selection : (isHovering ? AppTheme.line : AppTheme.lineSoft),
                lineWidth: isSelected ? 3 : 1
            )
    }

    private var contentTypeTitle: String {
        switch item.content {
        case .text: return "文本"
        case .image: return "图片"
        case .fileURLs: return "文件"
        }
    }

    private var contentIconName: String {
        switch item.content {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .fileURLs: return "doc.on.doc"
        }
    }

    private var contentHeaderColor: Color {
        switch item.content {
        case .text: return AppTheme.textCardHeader
        case .image: return AppTheme.imageCardHeader
        case .fileURLs: return AppTheme.fileCardHeader
        }
    }

    private var contentDetail: String {
        switch item.content {
        case .text(let text):
            return "\(text.count) 个字符"
        case .image:
            guard let size = item.imagePixelSize else { return "图片" }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .fileURLs(let urls):
            return "\(urls.count) 个文件"
        }
    }

    private var cardWidth: CGFloat {
        min(220, max(180, cardHeight * 1.2))
    }

    private var bodyPadding: CGFloat {
        cardHeight < 150 ? 7 : 11
    }

    private var maxTextLines: Int {
        cardHeight < 150 ? 3 : 5
    }

    private var visibleFileCount: Int {
        if cardHeight < 150 { return 1 }
        if cardHeight < 190 { return 2 }
        return 3
    }

    private var shortTimestamp: String {
        item.timestamp.formatted(
            .relative(presentation: .named)
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    private func unavailableBody(iconName: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 24))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(AppTheme.textMuted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
