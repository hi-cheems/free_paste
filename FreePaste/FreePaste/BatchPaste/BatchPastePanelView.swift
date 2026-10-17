//
//  BatchPastePanelView.swift
//  FreePaste
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

enum BatchPasteDragReorder {
    struct Step: Equatable {
        let index: Int
        let anchorTranslation: CGFloat
    }

    private static let swapThresholdRatio: CGFloat = 0.6

    static func step(
        currentIndex: Int,
        anchorTranslation: CGFloat,
        translation: CGFloat,
        rowHeight: CGFloat,
        itemCount: Int
    ) -> Step {
        guard itemCount > 0, rowHeight > 0 else {
            return Step(index: currentIndex, anchorTranslation: anchorTranslation)
        }

        var index = min(max(0, currentIndex), itemCount - 1)
        var anchor = anchorTranslation
        let threshold = rowHeight * swapThresholdRatio

        while index < itemCount - 1, translation - anchor >= threshold {
            index += 1
            anchor += rowHeight
        }
        while index > 0, translation - anchor <= -threshold {
            index -= 1
            anchor -= rowHeight
        }

        return Step(index: index, anchorTranslation: anchor)
    }
}

struct BatchPastePanelView: View {
    @ObservedObject var session: BatchPasteSession
    let onDirectionChange: (BatchPasteDirection) -> Void
    let onPaste: (ClipboardItem.ID?) -> Void
    let onDelete: (ClipboardItem.ID) -> Void
    let onClose: () -> Void

    @State private var draggedItemID: ClipboardItem.ID?
    @State private var dragCurrentIndex: Int?
    @State private var dragAnchorTranslation: CGFloat = 0
    @State private var draggedItemOffset: CGFloat = 0

    private static let itemListCoordinateSpace = "batchPasteItemList"

    var body: some View {
        VStack(spacing: 0) {
            header
            if session.isCapacityWarningVisible {
                capacityWarning
            }
            if session.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.panelStroke.opacity(0.9), lineWidth: 1)
        }
        .background(
            KeyboardEventMonitor(onKeyDown: handleKeyDown)
        )
        .tint(AppTheme.accent)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("输出顺序", selection: directionBinding) {
                ForEach(BatchPasteDirection.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 124)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .contentShape(Rectangle())
            .help("结束批量收集")
        }
        .padding(.horizontal, 10)
        .frame(height: BatchPastePanelLayout.headerHeight)
        .background(AppTheme.surfaceElevated)
        .background(WindowDragRegion())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.lineSoft)
                .frame(height: 1)
        }
    }

    private var capacityWarning: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("批量列表已满，新内容暂未加入")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.warning)
        .padding(.horizontal, 11)
        .frame(height: BatchPastePanelLayout.warningHeight)
        .background(AppTheme.warningSoft)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textMuted)
            Text("等待复制内容…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: BatchPastePanelLayout.emptyStateHeight)
    }

    private var itemList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(session.items) { item in
                    BatchPasteRow(
                        item: item,
                        isSelected: session.selectedItemID == item.id,
                        onSelect: { session.selectedItemID = item.id },
                        onPaste: {
                            session.selectedItemID = item.id
                            onPaste(item.id)
                        },
                        onDelete: { onDelete(item.id) }
                    )
                    .offset(y: draggedItemID == item.id ? draggedItemOffset : 0)
                    .scaleEffect(draggedItemID == item.id ? 1.015 : 1)
                    .shadow(
                        color: .black.opacity(draggedItemID == item.id ? 0.16 : 0),
                        radius: draggedItemID == item.id ? 6 : 0,
                        y: draggedItemID == item.id ? 2 : 0
                    )
                    .zIndex(draggedItemID == item.id ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: draggedItemID == item.id)
                    .simultaneousGesture(reorderGesture(for: item))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.visible)
        .scrollDisabled(draggedItemID != nil)
        .coordinateSpace(name: Self.itemListCoordinateSpace)
    }

    private var directionBinding: Binding<BatchPasteDirection> {
        Binding(
            get: { session.direction },
            set: { onDirectionChange($0) }
        )
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            session.clearSelection()
            return true
        case kVK_UpArrow:
            session.moveSelected(by: -1)
            return true
        case kVK_DownArrow:
            session.moveSelected(by: 1)
            return true
        case kVK_Delete, kVK_ForwardDelete:
            if let selectedItemID = session.selectedItemID {
                onDelete(selectedItemID)
            }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onPaste(session.selectedItemID)
            return true
        default:
            return false
        }
    }

    private func reorderGesture(for item: ClipboardItem) -> some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named(Self.itemListCoordinateSpace)
        )
            .onChanged { value in
                if draggedItemID == nil {
                    guard let index = session.items.firstIndex(where: { $0.id == item.id }) else {
                        return
                    }
                    draggedItemID = item.id
                    dragCurrentIndex = index
                    dragAnchorTranslation = 0
                    session.selectedItemID = item.id
                }

                guard draggedItemID == item.id, let dragCurrentIndex else { return }
                let step = BatchPasteDragReorder.step(
                    currentIndex: dragCurrentIndex,
                    anchorTranslation: dragAnchorTranslation,
                    translation: value.translation.height,
                    rowHeight: BatchPastePanelLayout.rowHeight,
                    itemCount: session.items.count
                )
                let residualOffset = value.translation.height - step.anchorTranslation

                if step.index != dragCurrentIndex {
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.84)) {
                        session.move(id: item.id, to: step.index)
                        self.dragCurrentIndex = step.index
                        dragAnchorTranslation = step.anchorTranslation
                        draggedItemOffset = residualOffset
                    }
                } else {
                    draggedItemOffset = residualOffset
                }
            }
            .onEnded { _ in
                guard draggedItemID == item.id else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.88)) {
                    draggedItemOffset = 0
                    draggedItemID = nil
                    dragCurrentIndex = nil
                    dragAnchorTranslation = 0
                }
            }
    }
}

private struct BatchPasteRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            summary
            Spacer(minLength: 6)
            if isHovering || isSelected {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .frame(width: 20, height: 24)
                    .help("拖动调整输出顺序")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.danger)
                .help("删除")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: BatchPastePanelLayout.rowHeight)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.lineSoft)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .exclusively(before: TapGesture(count: 1))
                .onEnded { value in
                    switch value {
                    case .first:
                        onSelect()
                        onPaste()
                    case .second:
                        onSelect()
                    }
                }
        )
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var summary: some View {
        switch item.content {
        case .text(let text):
            Text(text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

        case .image(let data):
            if let image = ClipboardThumbnailCache.shared.image(for: item.id, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AppTheme.textMuted)
                    .frame(width: 32, height: 32)
            }

        case .fileURLs(let urls):
            if let firstURL = urls.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: firstURL.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(fileSummary(urls))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.accentSoft }
        if isHovering { return AppTheme.surfaceHover }
        return AppTheme.surface
    }

    private func fileSummary(_ urls: [URL]) -> String {
        guard let firstURL = urls.first else { return "" }
        let remainingCount = urls.count - 1
        return remainingCount > 0
            ? "\(firstURL.lastPathComponent) 及另外 \(remainingCount) 个文件"
            : firstURL.lastPathComponent
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    static func dismantleNSView(_ nsView: DragView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class DragView: NSView {
        private static let dragThreshold: CGFloat = 2

        private var eventMonitor: Any?
        private var mouseDownLocation: CGPoint?
        private var windowOriginAtMouseDown: CGPoint?
        private var didDrag = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopMonitoring()
            } else {
                startMonitoring()
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        deinit {
            stopMonitoring()
        }

        fileprivate func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            resetDrag()
        }

        private func startMonitoring() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }

            switch event.type {
            case .leftMouseDown:
                let localPoint = convert(event.locationInWindow, from: nil)
                guard bounds.contains(localPoint) else {
                    resetDrag()
                    return event
                }
                mouseDownLocation = NSEvent.mouseLocation
                windowOriginAtMouseDown = window.frame.origin
                didDrag = false
                return event

            case .leftMouseDragged:
                guard let mouseDownLocation, let windowOriginAtMouseDown else {
                    return event
                }
                let currentMouseLocation = NSEvent.mouseLocation
                if !didDrag {
                    let distance = hypot(
                        currentMouseLocation.x - mouseDownLocation.x,
                        currentMouseLocation.y - mouseDownLocation.y
                    )
                    guard distance >= Self.dragThreshold else { return event }
                    didDrag = true
                }
                let origin = BatchPastePanelLayout.draggedOrigin(
                    windowOrigin: windowOriginAtMouseDown,
                    mouseDownLocation: mouseDownLocation,
                    currentMouseLocation: currentMouseLocation
                )
                window.setFrameOrigin(origin)
                return nil

            case .leftMouseUp:
                let shouldSuppressClick = didDrag
                resetDrag()
                return shouldSuppressClick ? nil : event

            default:
                return event
            }
        }

        private func resetDrag() {
            mouseDownLocation = nil
            windowOriginAtMouseDown = nil
            didDrag = false
        }
    }
}
