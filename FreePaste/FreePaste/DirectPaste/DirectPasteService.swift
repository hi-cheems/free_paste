//
//  DirectPasteService.swift
//  FreePaste
//
//  Created by Codex on 2026/3/15.
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

protocol RunningApplication: AnyObject {
    var bundleIdentifier: String? { get }
    var processIdentifier: pid_t { get }
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningApplication {}

/// Keeps "which app is frontmost" injectable so activation polling can be tested deterministically.
protocol FrontmostApplicationProviding {
    var frontmostApplication: (any RunningApplication)? { get }
}

struct WorkspaceFrontmostApplicationProvider: FrontmostApplicationProviding {
    var frontmostApplication: (any RunningApplication)? {
        NSWorkspace.shared.frontmostApplication
    }
}

enum DirectPasteResult: Equatable {
    case success
    case noTargetApplication
    case missingAccessibilityPermission
    case activationFailed
    case eventDispatchFailed
}

/// Boundary around the full direct-paste attempt: permission, app restore, and paste shortcut dispatch.
protocol DirectPasteServicing {
    func requestAccessibilityPermissionIfNeeded() -> Bool
    @discardableResult
    func pasteBack(to application: (any RunningApplication)?) -> DirectPasteResult
}

protocol AccessibilityPermissionControlling {
    func isTrusted(promptIfNeeded: Bool) -> Bool
}

struct AccessibilityPermissionController: AccessibilityPermissionControlling {
    func isTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

protocol PasteShortcutSending {
    func sendPasteShortcut() -> Bool
}

struct CGEventPasteShortcutSender: PasteShortcutSending {
    func sendPasteShortcut() -> Bool {
        CGEventCommandShortcutSender.send(keyCode: CGKeyCode(kVK_ANSI_V))
    }
}

enum CGEventCommandShortcutSender {
    static func send(keyCode: CGKeyCode) -> Bool {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
            ),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
            ),
            let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
            )
        else {
            return false
        }

        // Some apps are more reliable when they receive the explicit modifier key events,
        // not just a "V" key event with the command flag attached.
        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []
        [commandDown, keyDown, keyUp, commandUp].forEach {
            $0.setIntegerValueField(.eventSourceUserData, value: FreePasteSyntheticEvent.marker)
        }
        commandDown.post(tap: .cghidEventTap)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }
}

final class DirectPasteService: DirectPasteServicing {
    private let permissionController: any AccessibilityPermissionControlling
    private let shortcutSender: any PasteShortcutSending
    private let frontmostApplicationProvider: any FrontmostApplicationProviding
    private let activationDelay: TimeInterval
    private let activationTimeout: TimeInterval
    private let sleeper: (TimeInterval) -> Void

    init(
        permissionController: any AccessibilityPermissionControlling = AccessibilityPermissionController(),
        frontmostApplicationProvider: any FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider(),
        shortcutSender: any PasteShortcutSending = CGEventPasteShortcutSender(),
        activationDelay: TimeInterval = 0.12,
        activationTimeout: TimeInterval = 1.0,
        sleeper: @escaping (TimeInterval) -> Void = { interval in
            guard interval > 0 else { return }
            Thread.sleep(forTimeInterval: interval)
        }
    ) {
        self.permissionController = permissionController
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.shortcutSender = shortcutSender
        self.activationDelay = activationDelay
        self.activationTimeout = activationTimeout
        self.sleeper = sleeper
    }

    func requestAccessibilityPermissionIfNeeded() -> Bool {
        permissionController.isTrusted(promptIfNeeded: false)
    }

    @discardableResult
    func pasteBack(to application: (any RunningApplication)?) -> DirectPasteResult {
        guard let application else {
            return .noTargetApplication
        }

        // Callers must invoke requestAccessibilityPermissionIfNeeded() before this method.
        // pasteBack does not re-check permission to avoid a redundant syscall and to keep
        // the prompting UX in the caller's control (while the history panel is still visible).
        guard application.activate(options: []) else {
            return .activationFailed
        }

        // Activation returns early; wait until macOS reports the target app as frontmost before posting keys.
        guard waitUntilFrontmostApplicationIsTarget(application) else {
            return .activationFailed
        }

        guard shortcutSender.sendPasteShortcut() else {
            return .eventDispatchFailed
        }

        return .success
    }

    private func waitUntilFrontmostApplicationIsTarget(_ application: any RunningApplication) -> Bool {
        let deadline = Date().addingTimeInterval(activationTimeout)

        while Date() <= deadline {
            if frontmostApplicationProvider.frontmostApplication?.processIdentifier == application.processIdentifier {
                // Give the restored app a brief settle time before dispatching Cmd+V.
                sleeper(activationDelay)
                return true
            }
            sleeper(0.02)
        }

        return false
    }
}
