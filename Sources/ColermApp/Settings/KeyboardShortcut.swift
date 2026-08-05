import AppKit
import Carbon
import Foundation

enum AppShortcutAction: String, CaseIterable, Identifiable {
    case nextTerminal
    case previousTerminal
    case commandPalette

    var id: Self { self }

    var title: String {
        switch self {
        case .nextTerminal: "Next Terminal"
        case .previousTerminal: "Previous Terminal"
        case .commandPalette: "Command Palette"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .nextTerminal:
            KeyboardShortcut(
                keyCode: UInt16(kVK_Tab),
                modifiers: [.control],
                keyLabel: "Tab"
            )
        case .previousTerminal:
            KeyboardShortcut(
                keyCode: UInt16(kVK_Tab),
                modifiers: [.control, .shift],
                keyLabel: "Tab"
            )
        case .commandPalette:
            KeyboardShortcut(
                keyCode: UInt16(kVK_ANSI_K),
                modifiers: [.command],
                keyLabel: "K"
            )
        }
    }

    var cycleOffset: Int? {
        switch self {
        case .nextTerminal: 1
        case .previousTerminal: -1
        case .commandPalette: nil
        }
    }
}

struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifierRawValue: UInt
    let keyLabel: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        modifierRawValue = modifiers.semanticShortcutModifiers.rawValue
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.semanticShortcutModifiers
        guard modifiers.contains(.command)
                || modifiers.contains(.option)
                || modifiers.contains(.control) else {
            return nil
        }
        self.init(
            keyCode: event.keyCode,
            modifiers: modifiers,
            keyLabel: Self.label(for: event)
        )
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    var displayComponents: [String] {
        var components: [String] = []
        if modifiers.contains(.control) { components.append("⌃") }
        if modifiers.contains(.option) { components.append("⌥") }
        if modifiers.contains(.shift) { components.append("⇧") }
        if modifiers.contains(.command) { components.append("⌘") }
        components.append(keyLabel)
        return components
    }

    var conflictsWithFixedAppCommand: Bool {
        guard modifiers == [.command] else { return false }
        return [
            UInt16(kVK_ANSI_T),
            UInt16(kVK_ANSI_W),
            UInt16(kVK_ANSI_Q),
            UInt16(kVK_ANSI_Comma)
        ].contains(keyCode) || FixedAppShortcut.terminalNumber(
            keyCode: keyCode,
            modifiers: modifiers
        ) != nil
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.semanticShortcutModifiers == modifiers
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Space: "Space"
        case kVK_Delete: "Delete"
        case kVK_ForwardDelete: "⌦"
        case kVK_Home: "Home"
        case kVK_End: "End"
        case kVK_PageUp: "Page Up"
        case kVK_PageDown: "Page Down"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default: event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}

enum FixedAppShortcut {
    static func terminalNumber(for event: NSEvent) -> Int? {
        terminalNumber(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection([.shift, .control, .option, .command])
        )
    }

    static func terminalNumber(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Int? {
        guard modifiers == [.command] else { return nil }
        return switch Int(keyCode) {
        case kVK_ANSI_1: 1
        case kVK_ANSI_2: 2
        case kVK_ANSI_3: 3
        case kVK_ANSI_4: 4
        case kVK_ANSI_5: 5
        case kVK_ANSI_6: 6
        case kVK_ANSI_7: 7
        case kVK_ANSI_8: 8
        case kVK_ANSI_9: 9
        default: nil
        }
    }
}

extension NSEvent.ModifierFlags {
    fileprivate var semanticShortcutModifiers: NSEvent.ModifierFlags {
        intersection([.shift, .control, .option, .command])
    }
}
