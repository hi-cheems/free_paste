//
//  ShortcutRecorderRow.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderRow: View {
    let title: String
    let shortcut: KeyboardShortcut
    let defaultLabel: String
    /// Returns the name of the conflicting action, or nil if no conflict.
    var conflictChecker: ((KeyboardShortcut) -> String?)?
    let onChange: (KeyboardShortcut) -> Void

    @State private var isRecording = false
    @State private var conflictWarning: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("默认：\(defaultLabel)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Button(isRecording ? "按下快捷键…" : shortcut.displayText) {
                    conflictWarning = nil
                    isRecording.toggle()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(conflictWarning != nil ? AppTheme.danger : .primary)

                if isRecording {
                    ShortcutCaptureView(
                        onCapture: { capturedShortcut in
                            if let conflict = conflictChecker?(capturedShortcut) {
                                conflictWarning = conflict
                                // Do not save — conflict must be resolved first.
                            } else {
                                conflictWarning = nil
                                onChange(capturedShortcut)
                            }
                            isRecording = false
                        },
                        onCancel: {
                            isRecording = false
                        }
                    )
                    .frame(width: 1, height: 1)
                }
            }

            if let conflictWarning {
                Text("与「\(conflictWarning)」冲突")
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .onChange(of: shortcut) { _, _ in
            conflictWarning = nil
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (KeyboardShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }

    final class RecorderView: NSView {
        var onCapture: ((KeyboardShortcut) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // Delay to ensure SwiftUI layout is settled and window is ready to accept first responder.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                onCancel?()
                return
            }

            guard let shortcut = KeyboardShortcut.from(event: event) else {
                NSSound.beep()
                return
            }

            onCapture?(shortcut)
        }
    }
}
