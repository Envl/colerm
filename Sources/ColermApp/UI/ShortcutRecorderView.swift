import AppKit
import SwiftUI

final class ShortcutRecorderNSView: NSView {
    var onShortcut: (KeyboardShortcut) -> Bool = { _ in false }
    var onCancel: () -> Void = {}
    var onInvalid: () -> Void = {}
    private var mouseMonitor: Any?
    private var finished = false

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, window != nil {
            finish(onCancel)
        }
        return didResign
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        stopObserving()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startObserving()
        focus()
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event)
        return true
    }

    func focus() {
        Task { @MainActor [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat, !finished else { return }
        if event.keyCode == 53 {
            finish(onCancel)
            return
        }
        guard let shortcut = KeyboardShortcut(event: event) else {
            onInvalid()
            return
        }
        if onShortcut(shortcut) {
            finished = true
        }
    }

    private func startObserving() {
        guard let window, mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== window
                || !convert(bounds, to: nil).contains(event.locationInWindow) {
                finish(onCancel)
            }
            return event
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    private func stopObserving() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidResignKey() {
        finish(onCancel)
    }

    private func finish(_ action: () -> Void) {
        guard !finished else { return }
        finished = true
        action()
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let focusID: UUID
    let onShortcut: (KeyboardShortcut) -> Bool
    let onCancel: () -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        update(nsView)
        _ = focusID
        nsView.focus()
    }

    private func update(_ view: ShortcutRecorderNSView) {
        view.onShortcut = onShortcut
        view.onCancel = onCancel
        view.onInvalid = onInvalid
    }
}
