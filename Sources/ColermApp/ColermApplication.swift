import AppKit
import Sparkle

@MainActor
final class ColermApplication: NSObject, NSApplicationDelegate {
    private var windowController: ColermWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var commandPaletteController: TerminalCommandPalettePanelController?
    private var shortcutSettings: KeyboardShortcutSettings?
    private var workspaceLayoutSettings: WorkspaceLayoutSettings?
    private var shortcutMonitor: AppShortcutMonitor?
    private var commandRouter: WorkspaceCommandRouter?
    private var updaterController: SPUStandardUpdaterController?
    private var updateAvailabilityObserver: UpdateAvailabilityObserver?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)

        let shortcutSettings = KeyboardShortcutSettings()
        let workspaceLayoutSettings = WorkspaceLayoutSettings()
        let settingsWindowController = SettingsWindowController(
            shortcutSettings: shortcutSettings,
            workspaceLayoutSettings: workspaceLayoutSettings
        )
        var openCommandPalette: (() -> Void)?
        var installUpdate: (() -> Void)?
        let windowController = ColermWindowController(
            shortcutSettings: shortcutSettings,
            workspaceLayoutSettings: workspaceLayoutSettings,
            onOpenSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            },
            onOpenCommandPalette: {
                openCommandPalette?()
            },
            onInstallUpdate: {
                installUpdate?()
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
        self.workspaceLayoutSettings = workspaceLayoutSettings
        self.shortcutMonitor = shortcutMonitor
        self.commandRouter = commandRouter

        let updaterController: SPUStandardUpdaterController?
        if Bundle.main.bundleIdentifier == "com.colerm.app" {
            let observer = UpdateAvailabilityObserver()
            observer.onUpdateReady = { [weak windowController] ready in
                windowController?.setUpdateReady(ready)
            }
            observer.onUpdateError = { [weak self] error in
                DispatchQueue.main.async { [weak self] in
                    self?.presentUpdateError(error) {
                        installUpdate?()
                    }
                }
            }
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: observer,
                userDriverDelegate: nil
            )
            updateAvailabilityObserver = observer
            installUpdate = { [weak updaterController, weak observer] in
                if observer?.installAndRelaunch() == true {
                    return
                }

                observer?.markUserInitiatedUpdateCheck()
                guard let updater = updaterController?.updater,
                      updater.canCheckForUpdates else {
                    return
                }
                updater.checkForUpdatesInBackground()
            }
            if updaterController?.updater.automaticallyChecksForUpdates == true {
                updaterController?.updater.checkForUpdatesInBackground()
            }
        } else {
            updaterController = nil
            installUpdate = {}
        }
        self.updaterController = updaterController

        NSApp.mainMenu = makeMainMenu(router: commandRouter)
        windowController.showWindow(nil)
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

    private func presentUpdateError(_ error: any Error, retry: @escaping () -> Void) {
        let appPath = Bundle.main.bundleURL.standardizedFileURL.path
        let installedInSystemApplications = appPath.hasPrefix("/Applications/")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Colerm couldn’t finish the update"

        if installedInSystemApplications {
            alert.informativeText = "macOS may be blocking Colerm from replacing the copy in /Applications. Enable Colerm under Privacy & Security → App Management, then retry.\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "Open App Management")
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Cancel")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if installedInSystemApplications {
            switch response {
            case .alertFirstButtonReturn:
                openAppManagementSettings()
            case .alertSecondButtonReturn:
                retry()
            default:
                break
            }
        } else if response == .alertFirstButtonReturn {
            retry()
        }
    }

    private func openAppManagementSettings() {
        let appManagementURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement")
        let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let appManagementURL, NSWorkspace.shared.open(appManagementURL) {
            return
        }
        if let privacyURL {
            NSWorkspace.shared.open(privacyURL)
        }
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
