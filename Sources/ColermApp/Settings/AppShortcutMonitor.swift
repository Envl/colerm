import AppKit

@MainActor
final class AppShortcutMonitor {
    private let settings: KeyboardShortcutSettings
    private var monitor: Any?
    private var openCommandPalette: (() -> Void)?
    private var selectTerminal: ((Int) -> Void)?
    private var findInDiffs: (() -> Bool)?

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
        selectTerminal: @escaping (Int) -> Void,
        findInDiffs: @escaping () -> Bool
    ) {
        stop()
        self.openCommandPalette = openCommandPalette
        self.selectTerminal = selectTerminal
        self.findInDiffs = findInDiffs
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            @MainActor [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        openCommandPalette = nil
        selectTerminal = nil
        findInDiffs = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !settings.isRecording else { return event }

        if FixedAppShortcut.findInDiffs.matches(event), findInDiffs?() == true {
            return nil
        }

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
