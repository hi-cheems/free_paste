//
//  StatusCard.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import SwiftUI

struct StatusCard: View {
    enum Tone {
        case neutral
        case warning
    }

    let iconName: String
    let title: String
    let message: String
    let tone: Tone
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        iconName: String,
        title: String,
        message: String,
        tone: Tone = .neutral,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.title = title
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconBackgroundColor)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(actionColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return AppTheme.surface
        case .warning:
            return AppTheme.warningSoft
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            return AppTheme.line
        case .warning:
            return AppTheme.warning.opacity(0.22)
        }
    }

    private var iconColor: Color {
        switch tone {
        case .neutral:
            return AppTheme.accent
        case .warning:
            return AppTheme.warning
        }
    }

    private var iconBackgroundColor: Color {
        switch tone {
        case .neutral:
            return AppTheme.accent.opacity(0.12)
        case .warning:
            return AppTheme.warning.opacity(0.12)
        }
    }

    private var actionColor: Color {
        switch tone {
        case .neutral:
            return AppTheme.accent
        case .warning:
            return AppTheme.warning
        }
    }
}
