import AppKit
import Carbon
import GhosttyTerminal

@MainActor
final class TerminalSurfaceView: TerminalView {
    var onSelect: (() -> Void)?
    var onLayout: (() -> Void)?
    var onNewTerminal: (() -> Void)?
    var onCloseTerminal: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCycleTerminal: ((Int) -> Void)?
    var onUserInput: ((TerminalUserInputKind) -> Void)?
    weak var shortcutSettings: KeyboardShortcutSettings?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, registeredDraggedTypes.isEmpty {
            registerForDraggedTypes(TerminalPasteboard.supportedDragTypes)
        }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if window?.firstResponder === self,
           Self.isPasteKeyEquivalent(event),
           pasteFromPasteboard(.general)
        {
            return true
        }
        if handleWorkspaceShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if Self.isPasteKeyEquivalent(event), pasteFromPasteboard(.general) {
            return
        }
        if handleWorkspaceShortcut(event) { return }
        if let inputKind = Self.classifyKeyInput(event) {
            onUserInput?(inputKind)
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        if isMouseCaptured {
            onUserInput?(.interaction)
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isMouseCaptured {
            onUserInput?(.interaction)
        }
        super.mouseDragged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.25
        guard isHorizontal, let enclosingScrollView else {
            if isMouseCaptured,
               abs(event.scrollingDeltaY) > 0
                || abs(event.scrollingDeltaX) > 0
                || !event.momentumPhase.isEmpty {
                onUserInput?(.interaction)
            }
            super.scrollWheel(with: event)
            return
        }
        enclosingScrollView.scrollWheel(with: event)
    }

    override func selectionContextMenu() -> NSMenu {
        let menu = super.selectionContextMenu()
        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(pasteIntoTerminal(_:)),
            keyEquivalent: ""
        )
        pasteItem.target = self
        menu.addItem(pasteItem)
        return menu
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        TerminalPasteboard.canRead(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        TerminalPasteboard.canRead(from: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onSelect?()
        window?.makeFirstResponder(self)
        return pasteFromPasteboard(sender.draggingPasteboard)
    }

    @objc func pasteIntoTerminal(_: Any?) {
        _ = pasteFromPasteboard(.general)
    }

    @discardableResult
    func pasteFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        guard let content = TerminalPasteboard.extractPasteText(from: pasteboard),
              !content.isEmpty
        else {
            return false
        }
        let didPaste = paste(text: content)
        if didPaste {
            let submits = content.hasSuffix("\n") || content.hasSuffix("\r")
            onUserInput?(submits ? .submit : .typing)
        }
        return didPaste
    }

    static func classifyKeyInput(_ event: NSEvent) -> TerminalUserInputKind? {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command
        ])
        guard !modifiers.contains(.command) else { return nil }

        let isReturnKey = event.keyCode == UInt16(kVK_Return)
            || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
        if isReturnKey {
            return modifiers.isEmpty ? .submit : .typing
        }

        if event.keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
            return .interrupt
        }

        if modifiers == [.control],
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            return .interrupt
        }

        if event.keyCode == UInt16(kVK_PageUp)
            || event.keyCode == UInt16(kVK_PageDown)
            || event.keyCode == UInt16(kVK_Home)
            || event.keyCode == UInt16(kVK_End) {
            return .interaction
        }

        if modifiers.contains(.control) {
            return nil
        }

        if let characters = event.characters, !characters.isEmpty {
            return .typing
        }
        return nil
    }

    static func isPasteKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command
        ])
        guard modifiers == [.command] else { return false }

        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            if chars.unicodeScalars.allSatisfy(\.isASCII) {
                return chars.lowercased() == "v"
            }
        }
        return event.keyCode == UInt16(kVK_ANSI_V)
    }

    private func handleWorkspaceShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command
        ])

        if modifiers == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "t"
        {
            onNewTerminal?()
            return true
        }

        if modifiers == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "w"
        {
            onCloseTerminal?()
            return true
        }

        if modifiers == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "q"
        {
            NSApp.terminate(nil)
            return true
        }

        if modifiers == [.command], event.charactersIgnoringModifiers == "," {
            onOpenSettings?()
            return true
        }

        guard let action = shortcutSettings?.action(for: event),
              let offset = action.cycleOffset else { return false }
        onCycleTerminal?(offset)
        return true
    }
}
