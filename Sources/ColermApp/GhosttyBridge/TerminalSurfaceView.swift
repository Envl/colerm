import AppKit
import GhosttyTerminal

@MainActor
final class TerminalSurfaceView: TerminalView {
    var onSelect: (() -> Void)?
    var onNewTerminal: (() -> Void)?
    var onCloseTerminal: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCycleTerminal: ((Int) -> Void)?
    weak var shortcutSettings: KeyboardShortcutSettings?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleWorkspaceShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleWorkspaceShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.25
        guard isHorizontal, let enclosingScrollView else {
            super.scrollWheel(with: event)
            return
        }
        enclosingScrollView.scrollWheel(with: event)
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
