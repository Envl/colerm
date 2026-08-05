import AppKit

@MainActor
final class ColermWindowController: NSWindowController, NSWindowDelegate {
    let workspaceController: WorkspaceViewController
    private let onOpenCommandPalette: () -> Void
    private let paletteAccessoryController = NSTitlebarAccessoryViewController()

    init(
        shortcutSettings: KeyboardShortcutSettings,
        onOpenSettings: @escaping () -> Void,
        onOpenCommandPalette: @escaping () -> Void
    ) {
        self.onOpenCommandPalette = onOpenCommandPalette
        self.workspaceController = WorkspaceViewController(
            shortcutSettings: shortcutSettings,
            onOpenSettings: onOpenSettings
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Colerm"
        window.minSize = NSSize(width: 720, height: 420)
        window.isReleasedWhenClosed = false
        window.contentViewController = workspaceController
        super.init(window: window)
        window.delegate = self
        installPaletteTitlebarAccessory(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("ColermWindowController does not support NSCoder construction")
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        workspaceController.closeWindowIfAllowed()
    }

    private func installPaletteTitlebarAccessory(in window: NSWindow) {
        let button = PaletteTitlebarButton(
            title: "Search",
            target: self,
            action: #selector(openCommandPalette(_:))
        )
        button.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Search Terminals"
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.updateAppearance()
        button.toolTip = "Search Open Terminals"
        button.setAccessibilityLabel("Search Open Terminals")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 72),
            button.heightAnchor.constraint(equalToConstant: 18),
        ])

        paletteAccessoryController.layoutAttribute = .right
        paletteAccessoryController.view = container
        window.addTitlebarAccessoryViewController(paletteAccessoryController)
    }

    @objc private func openCommandPalette(_: Any?) {
        onOpenCommandPalette()
    }
}
