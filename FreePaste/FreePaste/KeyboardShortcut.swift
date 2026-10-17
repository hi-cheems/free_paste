//
//  KeyboardShortcut.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import Carbon
import Foundation

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = Self.normalized(modifierFlags).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && Self.normalized(event.modifierFlags) == modifierFlags
    }

    var displayText: String {
        let modifiers = modifierDisplayText
        return modifiers + keyDisplayText
    }

    var isRecordable: Bool {
        !modifierFlags.isEmpty || Self.specialKeyCodes.contains(keyCode)
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        let shortcut = KeyboardShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        return shortcut.isRecordable ? shortcut : nil
    }

    static let defaultGlobalToggle = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_V),
        modifierFlags: [.command, .shift]
    )

    static let defaultBatchPasteStart = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_C),
        modifierFlags: [.command, .shift]
    )

    /// Convert NSEvent.ModifierFlags to Carbon modifier mask for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    static let defaultSwitchPanel = KeyboardShortcut(keyCode: UInt16(kVK_Tab))
    static let defaultTogglePin = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_D),
        modifierFlags: .command
    )

    static let defaultNextItem = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_F),
        modifierFlags: .control
    )
    static let defaultPreviousItem = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_B),
        modifierFlags: .control
    )
    static let defaultDeleteSelectedItem = KeyboardShortcut(
        keyCode: UInt16(kVK_Delete),
        modifierFlags: .command
    )
    static let defaultFocusSearch = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_F),
        modifierFlags: .command
    )
    static let defaultPlainTextPaste = KeyboardShortcut(
        keyCode: UInt16(kVK_Return),
        modifierFlags: .shift
    )

    private static let specialKeyCodes: Set<UInt16> = [
        UInt16(kVK_Delete),
        UInt16(kVK_ForwardDelete),
        UInt16(kVK_Return),
        UInt16(kVK_Tab),
        UInt16(kVK_ANSI_KeypadEnter),
        UInt16(kVK_UpArrow),
        UInt16(kVK_DownArrow),
        UInt16(kVK_LeftArrow),
        UInt16(kVK_RightArrow),
        UInt16(kVK_ANSI_Slash)  // 允许裸 / 作为"聚焦搜索"快捷键
    ]

    private static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.control, .option, .shift, .command])
    }

    private var modifierDisplayText: String {
        var text = ""
        if modifierFlags.contains(.control) { text += "⌃" }
        if modifierFlags.contains(.option) { text += "⌥" }
        if modifierFlags.contains(.shift) { text += "⇧" }
        if modifierFlags.contains(.command) { text += "⌘" }
        return text
    }

    private var keyDisplayText: String {
        switch Int(keyCode) {
        case kVK_Delete:
            return "⌫"
        case kVK_ForwardDelete:
            return "⌦"
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return "↩"
        case kVK_Tab:
            return "⇥"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_Space:
            return "Space"
        default:
            return Self.printableKeyNames[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let printableKeyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Slash): "/"
    ]
}
