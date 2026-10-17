//
//  ItemPreviewPresenter.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import SwiftUI

protocol ItemPreviewPresenting: AnyObject {
    var previewItemID: ClipboardItem.ID? { get }
    var isShowingPreview: Bool { get }
    func showPreview(for item: ClipboardItem, nearWindow: NSWindow?)
    func closePreview()
}

/// Owns the preview NSPanel lifecycle.
final class ItemPreviewPresenter: ItemPreviewPresenting {
    private let settings: AppSettings
    private var windowController: NSWindowController?
    private(set) var previewItemID: ClipboardItem.ID?
    var previewWindow: NSWindow? { windowController?.window }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isShowingPreview: Bool {
        windowController?.window?.isVisible == true
    }

    func showPreview(for item: ClipboardItem, nearWindow: NSWindow?) {
        if isShowingPreview, previewItemID == item.id {
            nearWindow?.makeKey()
            return
        }
        closePreview()

        let contentView = ItemPreviewView(item: item)
        let panel = Self.makePanel(
            contentViewController: NSHostingController(rootView: contentView)
        )
        positionPanel(panel, nearWindow: nearWindow)
        windowController = NSWindowController(window: panel)
        previewItemID = item.id
        // Menu bar apps may still be inactive when the history panel is visible. Force the preview on
        // screen, then immediately return key status so list navigation keeps working.
        if NSApp.isActive {
            panel.orderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        nearWindow?.makeKey()
    }

    func closePreview() {
        windowController?.close()
        windowController = nil
        previewItemID = nil
    }

    private func positionPanel(_ panel: NSPanel, nearWindow: NSWindow?) {
        let panelSize = NSSize(width: 520, height: 440)
        guard let screen = nearWindow?.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        guard let nearWindow else {
            panel.center()
            return
        }
        let pf = nearWindow.frame
        let sf = screen.visibleFrame
        if pf.width >= 700 {
            let x = max(
                sf.minX,
                min(pf.midX - panelSize.width / 2, sf.maxX - panelSize.width)
            )
            let y = min(sf.maxY - panelSize.height, pf.maxY + 12)
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: false)
            return
        }
        var x = pf.minX - panelSize.width - 10
        if x < sf.minX { x = pf.maxX + 10 }
        if x + panelSize.width > sf.maxX { x = sf.midX - panelSize.width / 2 }
        let y = max(sf.minY, min(pf.maxY - panelSize.height, sf.maxY - panelSize.height))
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: false)
    }

    static func makePanel(contentViewController: NSViewController) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "全文预览"
        panel.contentViewController = contentViewController
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = .white
        return panel
    }
}
