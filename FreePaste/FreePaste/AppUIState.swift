//
//  AppUIState.swift
//  FreePaste
//
//  Created by Codex on 2026/3/15.
//

import Combine
import Foundation

@MainActor
final class AppUIState: ObservableObject {
    enum InlineMessageTone {
        case neutral
        case warning
    }

    /// Inline actions keep lightweight recovery UI in the history panel without adding a separate alert flow.
    struct InlineAction {
        let title: String
        let handler: @MainActor () -> Void

        @MainActor
        func perform() {
            handler()
        }
    }

    struct InlineMessage {
        let title: String
        let text: String
        let iconName: String
        let tone: InlineMessageTone
        let action: InlineAction?
    }

    @Published var inlineMessage: InlineMessage?
    @Published private(set) var historyPopoverPresentationID = 0
    @Published private(set) var isHistoryPopoverVisible = false

    func showInlineMessage(_ message: String) {
        inlineMessage = InlineMessage(
            title: "提示",
            text: message,
            iconName: "info.circle.fill",
            tone: .neutral,
            action: nil
        )
    }

    func showInlineMessage(
        _ message: String,
        actionTitle: String,
        action: @escaping @MainActor () -> Void
    ) {
        inlineMessage = InlineMessage(
            title: "需要处理",
            text: message,
            iconName: "exclamationmark.triangle.fill",
            tone: .warning,
            action: InlineAction(title: actionTitle, handler: action)
        )
    }

    func showWarningMessage(_ message: String) {
        inlineMessage = InlineMessage(
            title: "需要处理",
            text: message,
            iconName: "exclamationmark.triangle.fill",
            tone: .warning,
            action: nil
        )
    }

    func clearInlineMessage() {
        inlineMessage = nil
    }

    func markHistoryPopoverPresented() {
        isHistoryPopoverVisible = true
        historyPopoverPresentationID += 1
    }

    func markHistoryPopoverDismissed() {
        isHistoryPopoverVisible = false
    }
}
