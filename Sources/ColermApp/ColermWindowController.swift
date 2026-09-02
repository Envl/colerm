import AppKit
import Combine

@MainActor
final class ColermWindowController: NSWindowController, NSWindowDelegate {
    static let minimumWindowSize = NSSize(width: 720, height: 420)

    private static let frameAutosaveName = NSWindow.FrameAutosaveName(
        "ColermMainWindow.\(Bundle.main.bundleIdentifier ?? "com.colerm.app")"
    )

    let workspaceController: WorkspaceViewController
    private let onOpenCommandPalette: () -> Void
    private let onInstallUpdate: () -> Void
    private let paletteAccessoryController = NSTitlebarAccessoryViewController()
    private weak var updateButton: UpdateTitlebarButton?
    private var workspaceLayoutCancellable: AnyCancellable?

    init(
        shortcutSettings: KeyboardShortcutSettings,
        workspaceLayoutSettings: WorkspaceLayoutSettings,
        onOpenSettings: @escaping () -> Void,
        onOpenCommandPalette: @escaping () -> Void,
        onInstallUpdate: @escaping () -> Void
    ) {
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onInstallUpdate = onInstallUpdate
        self.workspaceController = WorkspaceViewController(
            shortcutSettings: shortcutSettings,
            workspaceLayoutSettings: workspaceLayoutSettings,
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
        window.minSize = Self.minimumWindowSize
        window.isReleasedWhenClosed = false
        window.contentViewController = workspaceController
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        } else {
            ensureMinimumWindowFrame()
        }
        workspaceLayoutCancellable = workspaceLayoutSettings.$isVerticalTabsEnabled.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.ensureMinimumWindowFrame()
            }
        }
        installPaletteTitlebarAccessory(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("ColermWindowController does not support NSCoder construction")
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        workspaceController.closeWindowIfAllowed()
    }

    func windowDidResize(_ notification: Notification) {
        guard let window, notification.object as? NSWindow === window else { return }
        ensureMinimumWindowFrame()
    }

    func windowWillClose(_: Notification) {
        ensureMinimumWindowFrame()
        window?.saveFrame(usingName: Self.frameAutosaveName)
    }

    static func frameByEnforcingMinimumSize(_ frame: NSRect, minimumSize: NSSize) -> NSRect {
        let widthDelta = max(minimumSize.width - frame.width, 0)
        let heightDelta = max(minimumSize.height - frame.height, 0)
        guard widthDelta > 0 || heightDelta > 0 else { return frame }

        var repairedFrame = frame
        repairedFrame.size.width += widthDelta
        repairedFrame.size.height += heightDelta
        repairedFrame.origin.y -= heightDelta
        return repairedFrame
    }

    func setUpdateReady(_ ready: Bool) {
        updateButton?.isHidden = !ready
        updateButton?.toolTip = ready ? "Restart to Update Colerm" : "Update Colerm"
        updateButton?.setAccessibilityLabel(ready ? "Restart to Update Colerm" : "Update Colerm")
    }

    private func installPaletteTitlebarAccessory(in window: NSWindow) {
        let searchButton = PaletteTitlebarButton(
            title: "Search",
            target: self,
            action: #selector(openCommandPalette(_:))
        )
        searchButton.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Search Terminals"
        )
        configureTitlebarButton(searchButton)
        searchButton.updateAppearance()
        searchButton.toolTip = "Search Open Terminals"
        searchButton.setAccessibilityLabel("Search Open Terminals")

        let updateButton = UpdateTitlebarButton(
            title: "Update",
            target: self,
            action: #selector(installUpdate(_:))
        )
        updateButton.image = NSImage(
            systemSymbolName: "arrow.down.circle.fill",
            accessibilityDescription: "Update Available"
        )
        configureTitlebarButton(updateButton)
        updateButton.updateAppearance()
        updateButton.toolTip = "Update Colerm"
        updateButton.setAccessibilityLabel("Update Colerm")
        updateButton.isHidden = true
        self.updateButton = updateButton

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 174, height: 28))
        container.addSubview(updateButton)
        container.addSubview(searchButton)
        NSLayoutConstraint.activate([
            updateButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            updateButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            updateButton.widthAnchor.constraint(equalToConstant: 78),
            updateButton.heightAnchor.constraint(equalToConstant: 18),
            searchButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            searchButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 84),
            searchButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        paletteAccessoryController.layoutAttribute = .right
        paletteAccessoryController.view = container
        window.addTitlebarAccessoryViewController(paletteAccessoryController)
    }

    @objc private func openCommandPalette(_: Any?) {
        onOpenCommandPalette()
    }

    @objc private func installUpdate(_: Any?) {
        onInstallUpdate()
    }

    private func configureTitlebarButton(_ button: NSButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
    }

    private func ensureMinimumWindowFrame() {
        guard let window else { return }
        let repairedFrame = Self.frameByEnforcingMinimumSize(
            window.frame,
            minimumSize: Self.minimumWindowSize
        )
        guard repairedFrame != window.frame else { return }

        let constrainedFrame = window.screen.map {
            window.constrainFrameRect(repairedFrame, to: $0)
        } ?? repairedFrame
        window.setFrame(constrainedFrame, display: false)
    }
}
