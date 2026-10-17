//
//  BatchPasteKeyInterceptor.swift
//  FreePaste
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum FreePasteSyntheticEvent {
    static let marker: Int64 = 0x4650_4250 // "FPBP"
}

protocol CopyShortcutSending {
    func sendCopyShortcut() -> Bool
}

struct CGEventCopyShortcutSender: CopyShortcutSending {
    func sendCopyShortcut() -> Bool {
        CGEventCommandShortcutSender.send(keyCode: CGKeyCode(kVK_ANSI_C))
    }
}

protocol BatchPasteSelectionCapturing {
    func captureSelection(completion: @escaping (Bool) -> Void)
}

protocol PasteboardChangeCountReading {
    var changeCount: Int { get }
}

extension NSPasteboard: PasteboardChangeCountReading {}

struct BatchPasteSelectionCaptureService: BatchPasteSelectionCapturing {
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    private let pasteboard: any PasteboardChangeCountReading
    private let shortcutSender: any CopyShortcutSending
    private let pollInterval: TimeInterval
    private let maximumPollAttempts: Int
    private let scheduler: Scheduler

    init(
        pasteboard: any PasteboardChangeCountReading = NSPasteboard.general,
        shortcutSender: any CopyShortcutSending = CGEventCopyShortcutSender(),
        pollInterval: TimeInterval = 0.02,
        maximumPollAttempts: Int = 25,
        scheduler: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.pasteboard = pasteboard
        self.shortcutSender = shortcutSender
        self.pollInterval = pollInterval
        self.maximumPollAttempts = max(0, maximumPollAttempts)
        self.scheduler = scheduler
    }

    func captureSelection(completion: @escaping (Bool) -> Void) {
        let initialChangeCount = pasteboard.changeCount
        guard shortcutSender.sendCopyShortcut() else {
            completion(false)
            return
        }
        waitForClipboardChange(
            from: initialChangeCount,
            remainingAttempts: maximumPollAttempts,
            completion: completion
        )
    }

    private func waitForClipboardChange(
        from initialChangeCount: Int,
        remainingAttempts: Int,
        completion: @escaping (Bool) -> Void
    ) {
        if pasteboard.changeCount != initialChangeCount {
            completion(true)
            return
        }
        guard remainingAttempts > 0 else {
            completion(false)
            return
        }
        scheduler(pollInterval) { [self] in
            waitForClipboardChange(
                from: initialChangeCount,
                remainingAttempts: remainingAttempts - 1,
                completion: completion
            )
        }
    }
}

/// Temporarily suppresses the user's global Command+V while batch mode is active.
final class BatchPasteKeyInterceptor {
    enum Decision: Equatable {
        case passThrough
        case suppress
        case triggerPaste
    }

    private let onPaste: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onPaste: @escaping () -> Void) {
        self.onPaste = onPaste
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: context
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    deinit {
        stop()
    }

    static func decision(
        keyCode: Int64,
        flags: CGEventFlags,
        isAutoRepeat: Bool,
        sourceUserData: Int64
    ) -> Decision {
        guard keyCode == Int64(kVK_ANSI_V),
              sourceUserData != FreePasteSyntheticEvent.marker,
              flags.contains(.maskCommand)
        else {
            return .passThrough
        }

        let alternatePasteModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl]
        guard flags.intersection(alternatePasteModifiers).isEmpty else {
            return .passThrough
        }
        return isAutoRepeat ? .suppress : .triggerPaste
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<BatchPasteKeyInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = interceptor.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let decision = BatchPasteKeyInterceptor.decision(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        )
        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .suppress:
            return nil
        case .triggerPaste:
            DispatchQueue.main.async {
                interceptor.onPaste()
            }
            return nil
        }
    }
}
