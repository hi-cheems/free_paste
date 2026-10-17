import AppKit
import Carbon.HIToolbox

enum ClipboardHistoryKeyAction: Equatable {
    case closePanel
    case exitEditing
    case editSearch
    case switchPanel
    case togglePin
    case nextItem
    case previousItem
    case deleteItem
    case paste
    case pastePlainText
    case preview

    /// A nil action leaves the event with the native text editor, including its undo and IME handling.
    static func resolve(_ event: NSEvent, isEditingSearch: Bool, settings: AppSettings) -> Self? {
        if event.keyCode == UInt16(kVK_Escape) {
            return isEditingSearch ? .exitEditing : .closePanel
        }
        guard !isEditingSearch else { return nil }

        if KeyboardShortcut.defaultFocusSearch.matches(event) || settings.focusSearchShortcut.matches(event) {
            return .editSearch
        }
        if KeyboardShortcut.defaultSwitchPanel.matches(event) || settings.switchPanelShortcut.matches(event) {
            return .switchPanel
        }
        if settings.togglePinShortcut.matches(event) { return .togglePin }
        if settings.nextItemShortcut.matches(event) { return .nextItem }
        if settings.previousItemShortcut.matches(event) { return .previousItem }
        if KeyboardShortcut(keyCode: UInt16(kVK_Delete)).matches(event) { return nil }
        if settings.deleteSelectedItemShortcut.matches(event) { return .deleteItem }
        if settings.plainTextPasteShortcut.matches(event) { return .pastePlainText }
        if settings.previewShortcut.matches(event) { return .preview }

        switch Int(event.keyCode) {
        case kVK_RightArrow, kVK_DownArrow:
            return .nextItem
        case kVK_LeftArrow, kVK_UpArrow:
            return .previousItem
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return .paste
        default:
            return nil
        }
    }
}
