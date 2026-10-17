//
//  BatchPastePanelController.swift
//  FreePaste
//

import AppKit
import Combine
import SwiftUI

enum BatchPastePanelLayout {
    static let defaultWidth: CGFloat = 320
    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 720
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 44
    static let emptyStateHeight: CGFloat = 48
    static let warningHeight: CGFloat = 30
    static let maximumScreenHeightRatio: CGFloat = 0.6
    static let screenInset: CGFloat = 16

    static func preferredHeight(
        itemCount: Int,
        showsWarning: Bool,
        visibleScreenHeight: CGFloat
    ) -> CGFloat {
        let bodyHeight = itemCount == 0 ? emptyStateHeight : CGFloat(itemCount) * rowHeight
        let warning = showsWarning ? warningHeight : 0
        return min(
            headerHeight + warning + bodyHeight,
            visibleScreenHeight * maximumScreenHeightRatio
        )
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func draggedOrigin(
        windowOrigin: CGPoint,
        mouseDownLocation: CGPoint,
        currentMouseLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: windowOrigin.x + currentMouseLocation.x - mouseDownLocation.x,
            y: windowOrigin.y + currentMouseLocation.y - mouseDownLocation.y
        )
    }
}

final class BatchPastePanelController: NSObject, NSWindowDelegate {
    private enum Keys {
        static let width = "batchPaste.panel.width"
        static let originX = "batchPaste.panel.originX"
        static let topY = "batchPaste.panel.topY"
        static let screenNumber = "batchPaste.panel.screenNumber"
    }

    private let session: BatchPasteSession
    private let panel: BatchPastePanel
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var desiredHeight = BatchPastePanelLayout.headerHeight + BatchPastePanelLayout.emptyStateHeight
    private var hasPositionedPanel = false

    init(
        session: BatchPasteSession,
        defaults: UserDefaults = .standard,
        onDirectionChange: @escaping (BatchPasteDirection) -> Void,
        onPaste: @escaping (ClipboardItem.ID?) -> Void,
        onDelete: @escaping (ClipboardItem.ID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.defaults = defaults

        let rootView = BatchPastePanelView(
            session: session,
            onDirectionChange: onDirectionChange,
            onPaste: onPaste,
            onDelete: onDelete,
            onClose: onClose
        )
        let hostingController = NSHostingController(rootView: rootView)
        let savedWidth = defaults.object(forKey: Keys.width) == nil
            ? BatchPastePanelLayout.defaultWidth
            : CGFloat(defaults.double(forKey: Keys.width))
        let width = min(
            BatchPastePanelLayout.maximumWidth,
            max(BatchPastePanelLayout.minimumWidth, savedWidth)
        )
        panel = BatchPastePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: desiredHeight
            ),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        super.init()

        configurePanel()
        observeSession()
    }

    var isVisible: Bool { panel.isVisible }

    func showWithoutActivating() {
        if !hasPositionedPanel {
            restorePosition()
            hasPositionedPanel = true
        }
        resizeForCurrentContent(animated: false)
        panel.orderFrontRegardless()
    }

    func bringToFront() {
        guard session.isActive else { return }
        showWithoutActivating()
    }

    func close() {
        panel.orderOut(nil)
        session.clearSelection()
    }

    func windowDidMove(_ notification: Notification) {
        savePlacement()
    }

    func windowDidResize(_ notification: Notification) {
        savePlacement()
    }

    func windowDidResignKey(_ notification: Notification) {
        session.clearSelection()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let screenWidth = (sender.screen?.visibleFrame.width ?? BatchPastePanelLayout.maximumWidth)
        let maximumWidth = min(BatchPastePanelLayout.maximumWidth, screenWidth)
        return NSSize(
            width: min(maximumWidth, max(BatchPastePanelLayout.minimumWidth, frameSize.width)),
            height: desiredHeight
        )
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
    }

    private func observeSession() {
        Publishers.CombineLatest(session.$items, session.$isCapacityWarningVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.resizeForCurrentContent(animated: true)
            }
            .store(in: &cancellables)
    }

    private func resizeForCurrentContent(animated: Bool) {
        guard let screen = panel.screen ?? preferredScreen() else { return }
        desiredHeight = BatchPastePanelLayout.preferredHeight(
            itemCount: session.items.count,
            showsWarning: session.isCapacityWarningVisible,
            visibleScreenHeight: screen.visibleFrame.height
        )
        var frame = panel.frame
        let oldTop = frame.maxY
        frame.size.height = desiredHeight
        frame.origin.y = oldTop - desiredHeight
        frame = BatchPastePanelLayout.clamped(frame, to: screen.visibleFrame)
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }

    private func restorePosition() {
        guard let screen = restoredScreen() ?? preferredScreen() else { return }
        let width = panel.frame.width
        let height = panel.frame.height
        let hasSavedOrigin = defaults.object(forKey: Keys.originX) != nil
            && defaults.object(forKey: Keys.topY) != nil
            && restoredScreen() != nil
        let origin: CGPoint
        if hasSavedOrigin {
            origin = CGPoint(
                x: defaults.double(forKey: Keys.originX),
                y: defaults.double(forKey: Keys.topY) - height
            )
        } else {
            origin = CGPoint(
                x: screen.visibleFrame.maxX - width - BatchPastePanelLayout.screenInset,
                y: screen.visibleFrame.maxY - height - BatchPastePanelLayout.screenInset
            )
        }
        let frame = BatchPastePanelLayout.clamped(
            CGRect(origin: origin, size: CGSize(width: width, height: height)),
            to: screen.visibleFrame
        )
        panel.setFrame(frame, display: false)
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }

    private func restoredScreen() -> NSScreen? {
        guard defaults.object(forKey: Keys.screenNumber) != nil else { return nil }
        let savedNumber = defaults.integer(forKey: Keys.screenNumber)
        return NSScreen.screens.first { screenNumber(for: $0) == savedNumber }
    }

    private func savePlacement() {
        guard hasPositionedPanel else { return }
        defaults.set(Double(panel.frame.width), forKey: Keys.width)
        defaults.set(Double(panel.frame.origin.x), forKey: Keys.originX)
        defaults.set(Double(panel.frame.maxY), forKey: Keys.topY)
        if let screen = panel.screen {
            defaults.set(screenNumber(for: screen), forKey: Keys.screenNumber)
        }
    }

    private func screenNumber(for screen: NSScreen) -> Int {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.intValue ?? 0
    }
}

private final class BatchPastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
