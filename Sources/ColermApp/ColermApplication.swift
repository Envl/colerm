import AppKit

@MainActor
final class ColermApplication: NSObject, NSApplicationDelegate {
    private var windowController: ColermWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var commandPaletteController: TerminalCommandPalettePanelController?
    private var shortcutSettings: KeyboardShortcutSettings?
    private var shortcutMonitor: AppShortcutMonitor?
    private var commandRouter: WorkspaceCommandRouter?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)

        let shortcutSettings = KeyboardShortcutSettings()
        let settingsWindowController = SettingsWindowController(settings: shortcutSettings)
        var openCommandPalette: (() -> Void)?
        let windowController = ColermWindowController(
            shortcutSettings: shortcutSettings,
            onOpenSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            },
            onOpenCommandPalette: {
                openCommandPalette?()
            }
        )
        let workspace = windowController.workspaceController
        let commandPaletteController = TerminalCommandPalettePanelController(
            store: workspace.store,
            activateSession: { [weak workspace] sessionID in
                workspace?.selectColumn(sessionID)
            },
            restoreTerminalFocus: { [weak workspace] in
                workspace?.restoreTerminalFocus()
            }
        )
        openCommandPalette = { [weak commandPaletteController, weak windowController] in
            commandPaletteController?.toggle(relativeTo: windowController?.window)
        }
        let shortcutMonitor = AppShortcutMonitor(settings: shortcutSettings)
        shortcutMonitor.start(
            openCommandPalette: {
                openCommandPalette?()
            },
            selectTerminal: { [weak workspace] number in
                workspace?.selectColumn(number: number)
            }
        )
        let commandRouter = WorkspaceCommandRouter()
        commandRouter.workspace = windowController.workspaceController
        commandRouter.onSearchTerminals = openCommandPalette
        self.windowController = windowController
        self.settingsWindowController = settingsWindowController
        self.commandPaletteController = commandPaletteController
        self.shortcutSettings = shortcutSettings
        self.shortcutMonitor = shortcutMonitor
        self.commandRouter = commandRouter

        NSApp.mainMenu = makeMainMenu(router: commandRouter)
        windowController.showWindow(nil)
        windowController.window?.center()
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace = windowController?.workspaceController else { return .terminateNow }
        return workspace.closeWindowIfAllowed() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    private func makeMainMenu(router: WorkspaceCommandRouter) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Colerm")
        appMenu.addItem(withTitle: "About Colerm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Colerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("New Column", action: #selector(WorkspaceCommandRouter.newColumn(_:)), key: "t", router: router))
        fileMenu.addItem(menuItem("Close Column", action: #selector(WorkspaceCommandRouter.closeColumn(_:)), key: "w", router: router))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let navigateMenuItem = NSMenuItem()
        let navigateMenu = NSMenu(title: "Navigate")
        let searchTerminals = NSMenuItem(
            title: "Search Terminals…",
            action: #selector(WorkspaceCommandRouter.searchTerminals(_:)),
            keyEquivalent: ""
        )
        searchTerminals.target = router
        navigateMenu.addItem(searchTerminals)
        navigateMenu.addItem(.separator())
        let previous = menuItem("Previous Column", action: #selector(WorkspaceCommandRouter.previousColumn(_:)), key: "[", router: router)
        previous.keyEquivalentModifierMask = [.command, .shift]
        navigateMenu.addItem(previous)
        let next = menuItem("Next Column", action: #selector(WorkspaceCommandRouter.nextColumn(_:)), key: "]", router: router)
        next.keyEquivalentModifierMask = [.command, .shift]
        navigateMenu.addItem(next)
        navigateMenu.addItem(.separator())

        for number in 1...9 {
            let item = NSMenuItem(
                title: "Column \(number)",
                action: #selector(WorkspaceCommandRouter.selectColumn(_:)),
                keyEquivalent: "\(number)"
            )
            item.target = router
            item.representedObject = number
            item.keyEquivalentModifierMask = [.command]
            navigateMenu.addItem(item)
        }
        navigateMenuItem.submenu = navigateMenu
        mainMenu.addItem(navigateMenuItem)

        return mainMenu
    }

    @objc private func showSettings(_: Any?) {
        settingsWindowController?.show()
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        key: String,
        router: WorkspaceCommandRouter
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = router
        item.keyEquivalentModifierMask = [.command]
        return item
    }
}

@main
struct ColermApplicationMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = ColermApplication()
        application.delegate = delegate
        application.run()
    }
}
