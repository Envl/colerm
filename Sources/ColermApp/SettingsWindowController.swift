import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        shortcutSettings: KeyboardShortcutSettings,
        workspaceLayoutSettings: WorkspaceLayoutSettings
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                shortcutSettings: shortcutSettings,
                workspaceLayoutSettings: workspaceLayoutSettings
            )
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoder construction")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
