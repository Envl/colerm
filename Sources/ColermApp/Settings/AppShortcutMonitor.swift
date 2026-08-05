import AppKit

@MainActor
final class AppShortcutMonitor {
    private let settings: KeyboardShortcutSettings
    private var monitor: Any?
    private var openCommandPalette: (() -> Void)?
    private var selectTerminal: ((Int) -> Void)?

    init(settings: KeyboardShortcutSettings) {
        self.settings = settings
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func start(
        openCommandPalette: @escaping () -> Void,
        selectTerminal: @escaping (Int) -> Void
    ) {
        stop()
        self.openCommandPalette = openCommandPalette
        self.selectTerminal = selectTerminal
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            @MainActor [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        openCommandPalette = nil
        selectTerminal = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !settings.isRecording else { return event }

        if let number = FixedAppShortcut.terminalNumber(for: event) {
            selectTerminal?(number)
            return nil
        }

        guard settings.shortcut(for: .commandPalette).matches(event) else {
            return event
        }
        openCommandPalette?()
        return nil
    }
}
