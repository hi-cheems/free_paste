//
//  KeyboardEventMonitor.swift
//  FreePaste
//
//  Created by Codex on 2026/3/15.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Captures key events while the history panel is active.
struct KeyboardEventMonitor: NSViewRepresentable {
    let focusRequestID: Int
    let handlesFieldEditorEvents: Bool
    let hidesFieldEditorInsertionPoint: Bool
    let onKeyDown: (NSEvent) -> Bool

    init(
        focusRequestID: Int = 0,
        handlesFieldEditorEvents: Bool = false,
        hidesFieldEditorInsertionPoint: Bool = false,
        onKeyDown: @escaping (NSEvent) -> Bool
    ) {
        self.focusRequestID = focusRequestID
        self.handlesFieldEditorEvents = handlesFieldEditorEvents
        self.hidesFieldEditorInsertionPoint = hidesFieldEditorInsertionPoint
        self.onKeyDown = onKeyDown
    }

    static func shouldRouteToPanel(
        isFieldEditor: Bool,
        keyCode: UInt16,
        handlesFieldEditorEvents: Bool = false,
        hasMarkedText: Bool = false
    ) -> Bool {
        guard !hasMarkedText else { return false }
        return !isFieldEditor || handlesFieldEditorEvents || keyCode == UInt16(kVK_Escape)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = FocusCatcherView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(
            onKeyDown: onKeyDown, focusRequestID: focusRequestID,
            handlesFieldEditorEvents: handlesFieldEditorEvents,
            hidesFieldEditorInsertionPoint: hidesFieldEditorInsertionPoint
        )
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? FocusCatcherView else { return }
        context.coordinator.attach(to: view)
        context.coordinator.update(
            onKeyDown: onKeyDown, focusRequestID: focusRequestID,
            handlesFieldEditorEvents: handlesFieldEditorEvents,
            hidesFieldEditorInsertionPoint: hidesFieldEditorInsertionPoint
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?
        private var windowUpdateObserver: NSObjectProtocol?
        private var handlesFieldEditorEvents = false
        private var hidesFieldEditorInsertionPoint = false
        private let insertionPointController = FieldEditorInsertionPointController()
        private weak var view: FocusCatcherView?
        private var appliedFocusRequestID: Int?
        private var pendingFocusRequestID: Int?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func attach(to view: FocusCatcherView) {
            self.view = view
            view.onWindowAvailable = { [weak self] in
                self?.applyPendingFocusRequest()
                self?.updateFieldEditorInsertionPoint()
            }
        }

        func update(
            onKeyDown: @escaping (NSEvent) -> Bool,
            focusRequestID: Int,
            handlesFieldEditorEvents: Bool,
            hidesFieldEditorInsertionPoint: Bool
        ) {
            self.onKeyDown = onKeyDown
            self.handlesFieldEditorEvents = handlesFieldEditorEvents
            self.hidesFieldEditorInsertionPoint = hidesFieldEditorInsertionPoint
            updateFieldEditorInsertionPoint()
            DispatchQueue.main.async { [weak self] in
                self?.updateFieldEditorInsertionPoint()
            }
            guard focusRequestID > 0 else { return }
            guard appliedFocusRequestID != focusRequestID else { return }
            appliedFocusRequestID = focusRequestID
            pendingFocusRequestID = focusRequestID
            applyPendingFocusRequest()
        }

        func start() {
            guard monitor == nil else { return }
            windowUpdateObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let window = self.view?.window,
                      notification.object as? NSWindow === window else { return }
                self.updateFieldEditorInsertionPoint()
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard
                    let self,
                    let window = self.view?.window,
                    window.isKeyWindow
                else {
                    return event
                }

                let textView = window.firstResponder as? NSTextView
                self.updateFieldEditorInsertionPoint()
                guard KeyboardEventMonitor.shouldRouteToPanel(
                    isFieldEditor: textView?.isFieldEditor == true,
                    keyCode: event.keyCode,
                    handlesFieldEditorEvents: self.handlesFieldEditorEvents,
                    hasMarkedText: textView?.hasMarkedText() == true
                ) else {
                    return event
                }

                // Returning nil consumes the event so arrows / Return stay inside the panel.
                return self.onKeyDown(event) ? nil : event
            }
            updateFieldEditorInsertionPoint()
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            if let windowUpdateObserver {
                NotificationCenter.default.removeObserver(windowUpdateObserver)
            }
            windowUpdateObserver = nil
            insertionPointController.restore()
        }

        private func updateFieldEditorInsertionPoint() {
            guard monitor != nil else { return }
            let window = view?.window
            insertionPointController.update(
                editor: window?.firstResponder as? NSTextView,
                isHidden: hidesFieldEditorInsertionPoint && window?.isKeyWindow == true
            )
        }

        private func applyPendingFocusRequest() {
            guard let view, pendingFocusRequestID != nil else { return }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, let window = view.window else { return }
                window.makeFirstResponder(view)
                self.pendingFocusRequestID = nil
            }
        }
    }

    final class FocusCatcherView: NSView {
        var onWindowAvailable: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowAvailable?()
        }
    }
}

/// Keep native text input and composition active without showing an editing caret in quick search.
final class FieldEditorInsertionPointController {
    private weak var editor: NSTextView?
    private var originalColor: NSColor?

    func update(editor: NSTextView?, isHidden: Bool) {
        guard isHidden, let editor, editor.isFieldEditor else {
            restore()
            return
        }
        if self.editor !== editor {
            restore()
            self.editor = editor
            originalColor = editor.insertionPointColor
        }
        guard editor.insertionPointColor != .clear else { return }
        editor.insertionPointColor = .clear
        editor.updateInsertionPointStateAndRestartTimer(false)
        editor.needsDisplay = true
    }

    func restore() {
        if let editor, let originalColor {
            editor.insertionPointColor = originalColor
            editor.updateInsertionPointStateAndRestartTimer(true)
            editor.needsDisplay = true
        }
        editor = nil
        originalColor = nil
    }
}
