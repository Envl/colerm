import AppKit
import Carbon
import SwiftUI

@MainActor
final class TerminalCommandPalettePanelController: NSObject, NSWindowDelegate {
    private let store: WorkspaceStore
    private let activateSession: (TerminalSessionID) -> Void
    private let restoreTerminalFocus: () -> Void
    private let panel: TerminalCommandPalettePanel
    private let hostingView: NSHostingView<TerminalCommandPaletteView>
    private weak var ownerWindow: NSWindow?
    private var isHiding = false
    private var keyMonitor: Any?
    private var pendingKeyEvents: [NSEvent] = []

    init(
        store: WorkspaceStore,
        activateSession: @escaping (TerminalSessionID) -> Void,
        restoreTerminalFocus: @escaping () -> Void
    ) {
        self.store = store
        self.activateSession = activateSession
        self.restoreTerminalFocus = restoreTerminalFocus
        panel = TerminalCommandPalettePanel(
            contentRect: NSRect(origin: .zero, size: TerminalCommandPaletteLayout.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostingView = NSHostingView(
            rootView: TerminalCommandPaletteView(
                store: store,
                presentationID: UUID(),
                activate: { _ in },
                dismiss: {}
            )
        )
        super.init()

        panel.identifier = NSUserInterfaceItemIdentifier("terminal-command-palette")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.delegate = self
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = TerminalCommandPaletteLayout.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo window: NSWindow? = nil) {
        if panel.isVisible {
            hide(restoreFocus: true)
        } else if let window {
            show(relativeTo: window)
        }
    }

    func show(relativeTo window: NSWindow) {
        guard !store.sessions.isEmpty else { return }
        isHiding = false
        ownerWindow = window
        hostingView.rootView = makeRoot()
        hostingView.layoutSubtreeIfNeeded()
        panel.setFrame(positionedFrame(relativeTo: window), display: false)
        window.addChildWindow(panel, ordered: .above)
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        ensureSearchFocus(attempt: 0)
    }

    func windowDidResignKey(_: Notification) {
        guard panel.isVisible, !isHiding else { return }
        hide(restoreFocus: true)
    }

    private func makeRoot() -> TerminalCommandPaletteView {
        TerminalCommandPaletteView(
            store: store,
            presentationID: UUID(),
            activate: { [weak self] sessionID in
                self?.activate(sessionID)
            },
            dismiss: { [weak self] in
                self?.hide(restoreFocus: true)
            }
        )
    }

    private func activate(_ sessionID: TerminalSessionID) {
        hide(restoreFocus: false)
        activateSession(sessionID)
    }

    private func hide(restoreFocus: Bool) {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        let owner = ownerWindow
        removeKeyMonitor()
        pendingKeyEvents.removeAll()
        owner?.removeChildWindow(panel)
        panel.orderOut(nil)
        owner?.makeKeyAndOrderFront(nil)
        isHiding = false
        if restoreFocus {
            DispatchQueue.main.async { [restoreTerminalFocus] in
                restoreTerminalFocus()
            }
        }
    }

    private func positionedFrame(relativeTo window: NSWindow) -> NSRect {
        var frame = panel.frame
        frame.origin.x = window.frame.midX - frame.width / 2
        frame.origin.y = window.frame.midY - frame.height / 2

        if let visibleFrame = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visibleFrame.minX + 12), visibleFrame.maxX - frame.width - 12)
            frame.origin.y = min(max(frame.minY, visibleFrame.minY + 12), visibleFrame.maxY - frame.height - 12)
        }
        return frame
    }

    private func focusSearchField() -> NSTextView? {
        hostingView.layoutSubtreeIfNeeded()
        guard let field = hostingView.descendant(
            identifiedBy: NSUserInterfaceItemIdentifier("terminal-palette-search-field")
        ) as? NSTextField else { return nil }
        panel.initialFirstResponder = field
        guard panel.makeFirstResponder(field),
              let editor = field.currentEditor() as? NSTextView else { return nil }
        editor.textColor = ColermTheme.palettePrimaryTextNS
        editor.insertionPointColor = ColermTheme.paletteAccentNS
        editor.selectedRange = NSRange(
            location: field.stringValue.utf16.count,
            length: 0
        )
        return editor
    }

    private func ensureSearchFocus(attempt: Int) {
        if let editor = focusSearchField() {
            let events = pendingKeyEvents
            pendingKeyEvents.removeAll()
            events.forEach { editor.keyDown(with: $0) }
            return
        }
        guard attempt < 12, panel.isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.ensureSearchFocus(attempt: attempt + 1)
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            @MainActor [weak self] event in
            guard let self,
                  panel.isVisible,
                  event.window === panel || panel.isKeyWindow else { return event }
            guard panel.searchFieldEditor == nil else { return event }

            if let editor = focusSearchField() {
                editor.keyDown(with: event)
            } else {
                if pendingKeyEvents.count < 16 {
                    pendingKeyEvents.append(event)
                }
                ensureSearchFocus(attempt: 0)
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private extension NSView {
    func descendant(identifiedBy identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        if self.identifier == identifier { return self }
        for subview in subviews {
            if let match = subview.descendant(identifiedBy: identifier) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private final class TerminalCommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command
        ])
        if modifiers == [.command],
           event.keyCode == UInt16(kVK_Delete),
           let editor = searchFieldEditor ?? activateSearchFieldEditor() {
            editor.deleteToBeginningOfLine(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    fileprivate var searchFieldEditor: NSTextView? {
        if let editor = firstResponder as? NSTextView { return editor }
        if let field = firstResponder as? NSTextField {
            return field.currentEditor() as? NSTextView
        }
        return nil
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown,
              searchFieldEditor == nil else {
            super.sendEvent(event)
            return
        }
        guard let editor = activateSearchFieldEditor() else {
            // The controller's event monitor will replay startup events once mounted.
            return
        }
        editor.keyDown(with: event)
    }

    private func activateSearchFieldEditor() -> NSTextView? {
        guard let field = contentView?.descendant(
            identifiedBy: NSUserInterfaceItemIdentifier("terminal-palette-search-field")
        ) as? NSTextField else { return nil }
        initialFirstResponder = field
        makeFirstResponder(field)
        return field.currentEditor() as? NSTextView
    }
}
