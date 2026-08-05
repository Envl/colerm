import AppKit
import SwiftUI

struct TerminalPaletteSearchField: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    let focusRequest: UUID
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "Search open terminals"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .medium)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.identifier = NSUserInterfaceItemIdentifier("terminal-palette-search-field")
        updateColors(for: field)
        field.delegate = context.coordinator
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        _ = colorScheme
        context.coordinator.parent = self
        updateColors(for: field)
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                context.coordinator.focus()
            }
        }
    }

    private func updateColors(for field: NSTextField) {
        field.textColor = ColermTheme.palettePrimaryTextNS
        field.placeholderAttributedString = NSAttributedString(
            string: "Search open terminals",
            attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: ColermTheme.paletteSecondaryTextNS
            ]
        )
        if let editor = field.currentEditor() as? NSTextView {
            editor.textColor = ColermTheme.palettePrimaryTextNS
            editor.insertionPointColor = ColermTheme.paletteAccentNS
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TerminalPaletteSearchField
        weak var field: NSTextField?
        var lastFocusRequest = UUID()

        init(parent: TerminalPaletteSearchField) {
            self.parent = parent
        }

        func focus() {
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                editor.textColor = ColermTheme.palettePrimaryTextNS
                editor.insertionPointColor = ColermTheme.paletteAccentNS
                editor.selectedRange = NSRange(
                    location: field.stringValue.utf16.count,
                    length: 0
                )
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onMoveUp()
                return true
            default:
                return false
            }
        }
    }
}
