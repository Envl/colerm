import XCTest
import AppKit
import Carbon
@testable import ColermApp

final class ColermAppTests: XCTestCase {
    @MainActor
    func testMainWindowMinimumFrameRepairsShortAutosaveFrame() {
        let savedFrame = NSRect(x: 189, y: 686, width: 945, height: 101)
        let repairedFrame = ColermWindowController.frameByEnforcingMinimumSize(
            savedFrame,
            minimumSize: ColermWindowController.minimumWindowSize
        )

        XCTAssertEqual(repairedFrame.size, NSSize(width: 945, height: 420))
        XCTAssertEqual(repairedFrame.origin.x, savedFrame.origin.x)
        XCTAssertEqual(repairedFrame.maxY, savedFrame.maxY)
    }

    @MainActor
    func testMainWindowMinimumFrameRepairsNarrowAutosaveFrame() {
        let savedFrame = NSRect(x: 189, y: 101, width: 441, height: 1257)
        let repairedFrame = ColermWindowController.frameByEnforcingMinimumSize(
            savedFrame,
            minimumSize: ColermWindowController.minimumWindowSize
        )

        XCTAssertEqual(repairedFrame.size, NSSize(width: 720, height: 1257))
        XCTAssertEqual(repairedFrame.origin.x, savedFrame.origin.x)
        XCTAssertEqual(repairedFrame.maxY, savedFrame.maxY)
    }

    @MainActor
    func testSwitchingTabOrientationPreservesWindowFrame() async throws {
        let suiteName = "ColermAppTests.tabOrientation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suiteName).json")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: persistenceURL)
        }

        let settings = WorkspaceLayoutSettings(defaults: defaults)
        settings.setVerticalTabsWidth(WorkspaceLayoutMetrics.maximumVerticalTabsWidth)
        let controller = WorkspaceViewController(
            store: WorkspaceStore(
                persistence: WorkspacePersistence(fileURL: persistenceURL),
                runtime: GhosttyRuntime(),
                gitInspector: GitInspector()
            ),
            shortcutSettings: KeyboardShortcutSettings(defaults: defaults),
            workspaceLayoutSettings: settings,
            onOpenSettings: {}
        )
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        window.minSize = ColermWindowController.minimumWindowSize
        window.contentViewController = controller

        for size in [window.minSize, NSSize(width: 980, height: 640)] {
            let frame = NSRect(origin: NSPoint(x: 100, y: 100), size: size)
            window.setFrame(frame, display: false)
            window.layoutIfNeeded()
            for isVertical in [true, false] {
                settings.setVerticalTabsEnabled(isVertical)
                window.layoutIfNeeded()
                await Task.yield()
                window.layoutIfNeeded()
                XCTAssertEqual(window.frame, frame, "Vertical tabs enabled: \(isVertical)")
            }
        }
    }

    func testWorkspaceTabTitlePrefersCurrentFolderOverGitRoot() {
        let gitRoot = URL(fileURLWithPath: "/tmp/shell-click")
        let currentFolder = gitRoot.appendingPathComponent("website")

        XCTAssertEqual(
            WorkspaceTabTitle.folderName(cwd: currentFolder, gitRoot: gitRoot),
            "website"
        )
        XCTAssertEqual(
            WorkspaceTabTitle.folderName(cwd: nil, gitRoot: gitRoot),
            "shell-click"
        )
        XCTAssertEqual(
            WorkspaceTabTitle.folderName(cwd: URL(fileURLWithPath: "/"), gitRoot: gitRoot),
            "/"
        )
        XCTAssertEqual(WorkspaceTabTitle.folderName(cwd: nil, gitRoot: nil), "New Column")
    }

    func testWorkspaceSessionOrderingInsertsAtBoundedPosition() {
        XCTAssertEqual(
            WorkspaceSessionOrdering.inserting("new", into: ["a", "b"], at: 1),
            ["a", "new", "b"]
        )
        XCTAssertEqual(
            WorkspaceSessionOrdering.inserting("new", into: ["a", "b"], at: -1),
            ["new", "a", "b"]
        )
        XCTAssertEqual(
            WorkspaceSessionOrdering.inserting("new", into: ["a", "b"], at: 99),
            ["a", "b", "new"]
        )
    }

    func testTerminalPaletteSearchMatchesTitlePathAndAllTerms() {
        let buildID = UUID()
        let serverID = UUID()
        let items = [
            TerminalPaletteItem(
                id: buildID,
                index: 1,
                title: "Build API",
                path: "~/Code/column"
            ),
            TerminalPaletteItem(
                id: serverID,
                index: 2,
                title: "Dev Server",
                path: "~/Code/neo-knowto"
            )
        ]

        XCTAssertEqual(
            TerminalPaletteSearch.filter(items, query: "build").map(\.id),
            [buildID]
        )
        XCTAssertEqual(
            TerminalPaletteSearch.filter(items, query: "server knowto").map(\.id),
            [serverID]
        )
        XCTAssertEqual(
            TerminalPaletteSearch.filter(items, query: "COLUMN").map(\.id),
            [buildID]
        )
        XCTAssertEqual(TerminalPaletteSearch.filter(items, query: "   "), items)
    }

    func testTerminalPaletteSearchMatchesSeparatorsAndFuzzySubsequences() {
        let livePhoto = TerminalPaletteItem(
            id: TerminalSessionID(),
            index: 1,
            title: "live-photo",
            path: "~/Code/live-photo"
        )
        let shellClick = TerminalPaletteItem(
            id: TerminalSessionID(),
            index: 2,
            title: "Shell Click",
            path: "~/Code/shell-click"
        )
        let items = [livePhoto, shellClick]

        XCTAssertEqual(
            TerminalPaletteSearch.filter(items, query: "livepho").map(\.id),
            [livePhoto.id]
        )
        XCTAssertEqual(
            TerminalPaletteSearch.filter(items, query: "sclk").map(\.id),
            [shellClick.id]
        )
        XCTAssertEqual(
            TerminalPaletteSearch.filter(items, query: "lvpto").map(\.id),
            [livePhoto.id]
        )
        XCTAssertTrue(TerminalPaletteSearch.filter(items, query: "clx").isEmpty)
    }

    func testTerminalPaletteSearchPromotesTitleMatchesAndKeepsTiesStable() {
        let pathOnly = TerminalPaletteItem(
            id: TerminalSessionID(),
            index: 1,
            title: "backend",
            path: "~/Code/live-photo"
        )
        let titleMatch = TerminalPaletteItem(
            id: TerminalSessionID(),
            index: 2,
            title: "live-photo",
            path: "~/Code/other"
        )
        let secondTitleMatch = TerminalPaletteItem(
            id: TerminalSessionID(),
            index: 3,
            title: "live-photo-tests",
            path: "~/Code/tests"
        )

        XCTAssertEqual(
            TerminalPaletteSearch.filter(
                [pathOnly, titleMatch, secondTitleMatch],
                query: "livepho"
            ).map(\.id),
            [titleMatch.id, secondTitleMatch.id, pathOnly.id]
        )
    }

    @MainActor
    func testKeyboardShortcutsPersistAndRejectConflicts() {
        let suiteName = "ColermAppTests.shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = KeyboardShortcutSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcut(for: .nextTerminal), AppShortcutAction.nextTerminal.defaultShortcut)
        XCTAssertEqual(settings.shortcut(for: .previousTerminal), AppShortcutAction.previousTerminal.defaultShortcut)
        XCTAssertEqual(settings.shortcut(for: .commandPalette), AppShortcutAction.commandPalette.defaultShortcut)
        XCTAssertEqual(
            settings.shortcut(for: .commandPalette),
            KeyboardShortcut(
                keyCode: UInt16(kVK_ANSI_P),
                modifiers: [.command],
                keyLabel: "P"
            )
        )

        let custom = KeyboardShortcut(
            keyCode: 124,
            modifiers: [.control, .option],
            keyLabel: "→"
        )
        XCTAssertEqual(settings.set(custom, for: .nextTerminal), .saved)
        XCTAssertEqual(settings.set(custom, for: .previousTerminal), .duplicate)
        XCTAssertEqual(
            settings.set(
                KeyboardShortcut(keyCode: 17, modifiers: [.command], keyLabel: "T"),
                for: .commandPalette
            ),
            .reserved
        )

        let restored = KeyboardShortcutSettings(defaults: defaults)
        XCTAssertEqual(restored.shortcut(for: .nextTerminal), custom)
        XCTAssertEqual(
            restored.shortcut(for: .previousTerminal),
            AppShortcutAction.previousTerminal.defaultShortcut
        )
        XCTAssertEqual(
            restored.shortcut(for: .commandPalette),
            AppShortcutAction.commandPalette.defaultShortcut
        )
    }

    @MainActor
    func testVerticalTabsSettingPersistsAndResets() {
        let suiteName = "ColermAppTests.workspaceLayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WorkspaceLayoutSettings(defaults: defaults)
        XCTAssertFalse(settings.isVerticalTabsEnabled)
        XCTAssertEqual(
            settings.verticalTabsWidth,
            WorkspaceLayoutMetrics.defaultVerticalTabsWidth
        )

        settings.setVerticalTabsEnabled(true)
        XCTAssertTrue(settings.isVerticalTabsEnabled)
        settings.setVerticalTabsWidth(WorkspaceLayoutMetrics.minimumVerticalTabsWidth - 1)
        XCTAssertEqual(
            settings.verticalTabsWidth,
            WorkspaceLayoutMetrics.minimumVerticalTabsWidth
        )

        let restored = WorkspaceLayoutSettings(defaults: defaults)
        XCTAssertTrue(restored.isVerticalTabsEnabled)
        XCTAssertEqual(
            restored.verticalTabsWidth,
            WorkspaceLayoutMetrics.minimumVerticalTabsWidth
        )

        restored.setVerticalTabsWidth(WorkspaceLayoutMetrics.maximumVerticalTabsWidth + 1)
        XCTAssertEqual(
            restored.verticalTabsWidth,
            WorkspaceLayoutMetrics.maximumVerticalTabsWidth
        )
        restored.reset()
        XCTAssertFalse(restored.isVerticalTabsEnabled)
        XCTAssertEqual(
            restored.verticalTabsWidth,
            WorkspaceLayoutMetrics.defaultVerticalTabsWidth
        )
        XCTAssertFalse(WorkspaceLayoutSettings(defaults: defaults).isVerticalTabsEnabled)
        XCTAssertEqual(
            WorkspaceLayoutSettings(defaults: defaults).verticalTabsWidth,
            WorkspaceLayoutMetrics.defaultVerticalTabsWidth
        )
    }

    func testCommandNumberShortcutsResolveAndStayReserved() {
        XCTAssertEqual(
            FixedAppShortcut.terminalNumber(
                keyCode: UInt16(kVK_ANSI_4),
                modifiers: [.command]
            ),
            4
        )
        XCTAssertNil(
            FixedAppShortcut.terminalNumber(
                keyCode: UInt16(kVK_ANSI_4),
                modifiers: [.command, .shift]
            )
        )
        XCTAssertTrue(
            KeyboardShortcut(
                keyCode: UInt16(kVK_ANSI_4),
                modifiers: [.command],
                keyLabel: "4"
            ).conflictsWithFixedAppCommand
        )
    }

    @MainActor
    func testPaletteConsumesUnhandledModifierKeyEquivalents() throws {
        let panel = TerminalCommandPalettePanel(
            contentRect: .zero,
            styleMask: TerminalCommandPalettePanel.paletteStyleMask,
            backing: .buffered,
            defer: false
        )
        let commandEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "n",
            charactersIgnoringModifiers: "n",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_N)
        ))
        let editor = KeyDownRecordingTextView(frame: .zero)
        panel.contentView = editor

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.makeFirstResponder(editor))
        XCTAssertTrue(panel.ownsKeyEquivalent(commandEvent))
        XCTAssertTrue(panel.performKeyEquivalent(with: commandEvent))
        XCTAssertEqual(editor.keyDownCallCount, 0)
    }

    func testRuntimeMetadataRejectsOversizedAndRemotePayloads() {
        let valid = Data(#"{"runtime":{"name":"Node","path":"/tmp/colerm-test/.local/bin/node","version":"v24.15.0"}}"#.utf8)
        let metadata = RuntimeMetadataParser.decode(valid)

        XCTAssertEqual(metadata?.runtime?.name, "Node")
        XCTAssertEqual(metadata?.runtime?.version, "v24.15.0")
        XCTAssertEqual(metadata?.runtime?.path?.path, "/tmp/colerm-test/.local/bin/node")

        let remote = Data(#"{"runtime":{"name":"Node","path":"ssh://host/bin/node","version":"v24.15.0"}}"#.utf8)
        XCTAssertNil(RuntimeMetadataParser.decode(remote))

        let cleared = Data(#"{"runtime":null}"#.utf8)
        XCTAssertNotNil(RuntimeMetadataParser.decode(cleared))
        XCTAssertNil(RuntimeMetadataParser.decode(cleared)?.runtime)

        let versionless = Data(#"{"runtime":{"name":"Rust","path":"/usr/bin/rustc"}}"#.utf8)
        XCTAssertEqual(RuntimeMetadataParser.decode(versionless)?.runtime?.name, "Rust")
        XCTAssertNil(RuntimeMetadataParser.decode(versionless)?.runtime?.version)

        let oversized = Data(repeating: 0x20, count: RuntimeMetadataParser.maximumPayloadBytes + 1)
        XCTAssertNil(RuntimeMetadataParser.decode(oversized))
    }

    func testRuntimeMetadataStripsControlCharacters() {
        let payload = Data(#"{"runtime":{"name":"Node","version":"v24.15.0\u0000","path":"/tmp/node"}}"#.utf8)
        XCTAssertEqual(RuntimeMetadataParser.decode(payload)?.runtime?.version, "v24.15.0")
    }

    func testTerminalAccentHasSevenStableSemanticOptions() {
        let sessionID = UUID(uuidString: "9D1C0C86-5A4D-48CD-A214-7023936DD35B")!

        XCTAssertEqual(TerminalAccent.allCases.count, 7)
        XCTAssertTrue(TerminalAccent.allCases.contains(.neutral))
        XCTAssertEqual(
            TerminalAccent.forSession(sessionID),
            TerminalAccent.forSession(sessionID)
        )
    }

    func testColermThemePreservesDarkTitleAndProvidesLightVariant() throws {
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = ColermTheme.resolved(ColermTheme.terminalTitleNS, for: darkAppearance)
        let light = ColermTheme.resolved(ColermTheme.terminalTitleNS, for: lightAppearance)
        let darkTitleText = ColermTheme.resolved(ColermTheme.terminalTitleTextNS, for: darkAppearance)
        let lightTitleText = ColermTheme.resolved(ColermTheme.terminalTitleTextNS, for: lightAppearance)
        let darkSplitter = ColermTheme.resolved(ColermTheme.terminalSplitterNS, for: darkAppearance)
        let lightSplitter = ColermTheme.resolved(ColermTheme.terminalSplitterNS, for: lightAppearance)

        var darkRed: CGFloat = 0
        var darkGreen: CGFloat = 0
        var darkBlue: CGFloat = 0
        var darkAlpha: CGFloat = 0
        dark.getRed(&darkRed, green: &darkGreen, blue: &darkBlue, alpha: &darkAlpha)
        XCTAssertEqual(darkRed, 24 / 255, accuracy: 0.001)
        XCTAssertEqual(darkGreen, 24 / 255, accuracy: 0.001)
        XCTAssertEqual(darkBlue, 24 / 255, accuracy: 0.001)

        var lightRed: CGFloat = 0
        var lightGreen: CGFloat = 0
        var lightBlue: CGFloat = 0
        var lightAlpha: CGFloat = 0
        light.getRed(&lightRed, green: &lightGreen, blue: &lightBlue, alpha: &lightAlpha)
        XCTAssertGreaterThan(lightRed, 0.9)
        XCTAssertGreaterThan(lightGreen, 0.9)
        XCTAssertGreaterThan(lightBlue, 0.9)

        var lightTitleTextRed: CGFloat = 0
        var lightTitleTextGreen: CGFloat = 0
        var lightTitleTextBlue: CGFloat = 0
        lightTitleText.getRed(
            &lightTitleTextRed,
            green: &lightTitleTextGreen,
            blue: &lightTitleTextBlue,
            alpha: nil
        )
        XCTAssertEqual(lightTitleTextRed, 0.32, accuracy: 0.001)
        XCTAssertEqual(lightTitleTextGreen, 0.32, accuracy: 0.001)
        XCTAssertEqual(lightTitleTextBlue, 0.32, accuracy: 0.001)
        XCTAssertNotEqual(darkTitleText, lightTitleText)

        var darkSplitterRed: CGFloat = 0
        var lightSplitterRed: CGFloat = 0
        darkSplitter.getRed(&darkSplitterRed, green: nil, blue: nil, alpha: nil)
        lightSplitter.getRed(&lightSplitterRed, green: nil, blue: nil, alpha: nil)
        XCTAssertEqual(darkSplitterRed, 0.30, accuracy: 0.001)
        XCTAssertEqual(lightSplitterRed, 0.76, accuracy: 0.001)
        XCTAssertEqual(ColermTheme.ghosttyTheme, "light:Colerm Light,dark:Colerm Dark")
    }

    @MainActor
    func testPaletteTitlebarColorsAdaptToAppearance() throws {
        func redComponent(of color: NSColor) -> CGFloat {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return red
        }

        let button = PaletteTitlebarButton(title: "Search", target: nil, action: nil)
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let darkTint = ColermTheme.resolved(button.normalTintColor, for: darkAppearance)
        let lightTint = ColermTheme.resolved(button.normalTintColor, for: lightAppearance)
        let darkBackground = ColermTheme.resolved(
            button.normalBackgroundColor,
            for: darkAppearance
        )
        let lightBackground = ColermTheme.resolved(
            button.normalBackgroundColor,
            for: lightAppearance
        )

        XCTAssertGreaterThan(redComponent(of: darkTint), 0.9)
        XCTAssertLessThan(redComponent(of: lightTint), 0.1)
        XCTAssertGreaterThan(redComponent(of: darkBackground), 0.9)
        XCTAssertLessThan(redComponent(of: lightBackground), 0.1)
        XCTAssertGreaterThan(darkBackground.alphaComponent, 0)
        XCTAssertLessThan(darkBackground.alphaComponent, 0.2)
    }

    func testWorkspaceSessionOrderingUsesInsertionBoundaries() {
        let original = ["A", "B", "C", "D"]

        XCTAssertEqual(
            WorkspaceSessionOrdering.move(original, from: 1, toInsertionIndex: 4),
            ["A", "C", "D", "B"]
        )
        XCTAssertEqual(
            WorkspaceSessionOrdering.move(original, from: 3, toInsertionIndex: 1),
            ["A", "D", "B", "C"]
        )
        XCTAssertEqual(
            WorkspaceSessionOrdering.move(original, from: 1, toInsertionIndex: 2),
            original
        )
    }

    func testGitStatusParserCountsUniquePathsAndDetachedHead() {
        let output = [
            "# branch.oid abc",
            "# branch.head (detached)",
            "1 .M N... 100644 100644 100644 a b file.swift",
            "? new.txt",
            "2 R. N... 100644 100644 100644 100644 R100 old.swift",
            "new.swift"
        ].joined(separator: "\0")
        let result = GitStatusParser.parse(output)

        XCTAssertEqual(result.branch, "HEAD")
        XCTAssertTrue(result.isDetachedHead)
        XCTAssertEqual(result.paths, ["file.swift", "new.txt", "old.swift", "new.swift"])
    }

    func testWorkspacePersistenceRoundTripsOnlyReconstructableState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColumnTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = WorkspacePersistence(
            fileURL: directory.appendingPathComponent("workspace.json")
        )
        let selected = UUID()
        let document = PersistedWorkspace(
            selectedSessionID: selected,
            sessions: [
                PersistedSession(
                    id: selected,
                    cwd: URL(fileURLWithPath: "/tmp/project"),
                    customTitle: "Build",
                    columnWidth: 720
                )
            ]
        )

        try persistence.save(document)

        XCTAssertEqual(persistence.load(), document)
    }

    @MainActor
    func testWorkspaceLaunchSelectsFirstPersistedSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColumnTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = UUID()
        let second = UUID()
        let persistence = WorkspacePersistence(
            fileURL: directory.appendingPathComponent("workspace.json")
        )
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: second,
                sessions: [
                    PersistedSession(id: first, cwd: URL(fileURLWithPath: "/tmp/first"), columnWidth: 600),
                    PersistedSession(id: second, cwd: URL(fileURLWithPath: "/tmp/second"), columnWidth: 600)
                ]
            )
        )

        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector()
        )

        XCTAssertEqual(store.selectedSessionID, first)
        XCTAssertTrue(store.sessions[0].isActive)
        XCTAssertFalse(store.sessions[1].isActive)

        let firstActivationID = store.selectionActivationID
        store.select(first)
        XCTAssertNotEqual(store.selectionActivationID, firstActivationID)

        store.select(second)
        XCTAssertTrue(store.closeSelectedColumn(confirm: false))
        XCTAssertEqual(store.sessions.map(\.id), [first])
        XCTAssertEqual(store.selectedSessionID, first)
    }

    @MainActor
    func testWorkspaceAddColumnInsertsAfterSelectedSession() throws {
        let fixtureName = "ColumnAddTests-\(UUID().uuidString)"
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fixtureName).json")
        defer { try? FileManager.default.removeItem(at: persistenceURL) }

        let first = UUID()
        let second = UUID()
        let persistence = WorkspacePersistence(fileURL: persistenceURL)
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: first,
                sessions: [
                    PersistedSession(id: first, cwd: URL(fileURLWithPath: "/tmp/first"), columnWidth: 600),
                    PersistedSession(id: second, cwd: URL(fileURLWithPath: "/tmp/second"), columnWidth: 600)
                ]
            )
        )

        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector()
        )

        store.addColumn()

        let newSessionID = try XCTUnwrap(store.selectedSessionID)
        XCTAssertEqual(store.sessions.map(\.id), [first, newSessionID, second])
        XCTAssertEqual(store.selectedSession?.cwd, URL(fileURLWithPath: "/tmp/first"))
    }

    @MainActor
    func testTabActivationForcesGitStatusRefresh() async throws {
        let fixtureName = "ColumnGitRefresh-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(fixtureName, isDirectory: true)
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fixtureName).json")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: persistenceURL)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try runGit(arguments: ["-C", directory.path, "init", "-q"])
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("first.txt").path,
            contents: Data()
        )

        let sessionID = UUID()
        let persistence = WorkspacePersistence(fileURL: persistenceURL)
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: sessionID,
                sessions: [
                    PersistedSession(id: sessionID, cwd: directory, columnWidth: 600)
                ]
            )
        )

        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector(cacheLifetime: 60, debounceMilliseconds: 0)
        )
        try await waitForGitStatus(on: store.sessions[0], changedFiles: 1)

        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("second.txt").path,
            contents: Data()
        )
        store.select(sessionID)

        try await waitForGitStatus(on: store.sessions[0], changedFiles: 2)
    }

    func testDebugWorkspacePersistenceIsIsolatedFromRelease() {
        XCTAssertEqual(
            WorkspacePersistence.supportDirectoryName(bundleIdentifier: "com.colerm.app"),
            "Colerm"
        )
        XCTAssertEqual(
            WorkspacePersistence.supportDirectoryName(bundleIdentifier: "com.colerm.app.debug"),
            "Colerm Debug"
        )
    }

    @MainActor
    func testTerminalSessionDetectsForegroundCommandFromPTYProcess() {
        let engine = ActivityTestEngine()
        engine.reportedForegroundPID = 100
        let session = TerminalSession(
            launchOptions: SessionLaunchOptions(),
            engine: engine
        )

        XCTAssertFalse(session.refreshForegroundActivity())
        XCTAssertFalse(session.isForegroundCommandRunning)

        engine.reportedForegroundPID = 200
        XCTAssertTrue(session.refreshForegroundActivity())
        XCTAssertTrue(session.isForegroundCommandRunning)

        engine.reportedForegroundPID = 100
        session.commandFinished(exitCode: 0)
        XCTAssertFalse(session.refreshForegroundActivity())
        XCTAssertFalse(session.isForegroundCommandRunning)
    }

    @MainActor
    func testTerminalSessionCommandEventsOverrideForegroundPIDFallback() {
        let engine = ActivityTestEngine()
        engine.reportedForegroundPID = 100
        let session = TerminalSession(
            launchOptions: SessionLaunchOptions(),
            engine: engine
        )

        XCTAssertFalse(session.refreshForegroundActivity())
        engine.reportedForegroundPID = 200
        session.commandStarted()
        XCTAssertTrue(session.isForegroundCommandRunning)

        session.commandFinished(exitCode: 0)
        XCTAssertFalse(session.isForegroundCommandRunning)

        engine.reportedForegroundPID = 100
        XCTAssertFalse(session.refreshForegroundActivity())
        XCTAssertFalse(session.isForegroundCommandRunning)
    }

    @MainActor
    func testTerminalSessionWaitsForEngineReadiness() {
        let engine = ActivityTestEngine()
        engine.isRunning = false
        let session = TerminalSession(
            launchOptions: SessionLaunchOptions(),
            engine: engine
        )

        XCTAssertEqual(session.processState, .launching)

        engine.reportedForegroundPID = 100
        engine.isRunning = true
        XCTAssertFalse(session.refreshForegroundActivity())
        XCTAssertEqual(session.processState, .running)
    }

    func testGitBranchParserSeparatesLocalAndUncheckedOutRemoteBranches() {
        let output = [
            "refs/heads/main\tmain\t*\t",
            "refs/heads/feature/ui\tfeature/ui\t \t",
            "refs/remotes/origin/HEAD\torigin\t \trefs/remotes/origin/main",
            "refs/remotes/origin/main\torigin/main\t \t",
            "refs/remotes/origin/release/1.0\torigin/release/1.0\t \t"
        ].joined(separator: "\n")

        let parsed = GitBranchParser.parse(
            output,
            currentBranch: "main",
            isDetachedHead: false
        )

        XCTAssertEqual(
            parsed.localBranches,
            [
                GitBranch(name: "feature/ui", localName: "feature/ui", isRemote: false, isCurrent: false),
                GitBranch(name: "main", localName: "main", isRemote: false, isCurrent: true)
            ]
        )
        XCTAssertEqual(
            parsed.remoteBranches,
            [
                GitBranch(
                    name: "origin/release/1.0",
                    localName: "release/1.0",
                    isRemote: true,
                    isCurrent: false
                )
            ]
        )
    }

    @MainActor
    func testBranchMenuPresenterBuildsCheckedLocalAndRemoteSubmenu() throws {
        let branchList = GitBranchList(
            currentBranch: "main",
            isDetachedHead: false,
            localBranches: [
                GitBranch(name: "feature/diffs", localName: "feature/diffs", isRemote: false, isCurrent: false),
                GitBranch(name: "main", localName: "main", isRemote: false, isCurrent: true)
            ],
            remoteBranches: [
                GitBranch(name: "origin/hotfix", localName: "hotfix", isRemote: true, isCurrent: false)
            ]
        )

        var selectedBranches: [GitBranch] = []
        let menu = BranchMenuPresenter.buildMenu(from: branchList) { branch in
            selectedBranches.append(branch)
        }

        XCTAssertEqual(menu.items.count, 4)
        XCTAssertEqual(menu.items[0].title, "feature/diffs")
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertEqual(menu.items[1].title, "main")
        XCTAssertEqual(menu.items[1].state, .on)
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Remote Branches")

        // Clicking current branch is a no-op
        _ = menu.items[1].target?.perform(menu.items[1].action, with: menu.items[1])
        XCTAssertTrue(selectedBranches.isEmpty)

        // Clicking another local branch triggers switch
        _ = menu.items[0].target?.perform(menu.items[0].action, with: menu.items[0])
        XCTAssertEqual(selectedBranches.map(\.name), ["feature/diffs"])

        // Clicking remote submenu branch triggers switch
        let remoteItem = try XCTUnwrap(menu.items[3].submenu?.items.first)
        _ = remoteItem.target?.perform(remoteItem.action, with: remoteItem)
        XCTAssertEqual(selectedBranches.map(\.name), ["feature/diffs", "origin/hotfix"])
    }

    func testGitDiffParserHandlesModifiedRenamedBinaryAndSpacesInPaths() {
        let diff = """
        diff --git a/Docs/Release Notes.md b/Docs/Release Notes.md
        index 1111111..2222222 100644
        --- a/Docs/Release Notes.md
        +++ b/Docs/Release Notes.md
        @@ -1,3 +1,4 @@
         # Release
        -Old line
        +New line
        +Added line
         Footer
        diff --git a/Sources/Old.swift b/Sources/New.swift
        similarity index 100%
        rename from Sources/Old.swift
        rename to Sources/New.swift
        diff --git a/Assets/logo.png b/Assets/logo.png
        index 3333333..4444444 100644
        Binary files a/Assets/logo.png and b/Assets/logo.png differ
        """

        let files = GitDiffParser.parseUnifiedDiff(diff)
        XCTAssertEqual(files.count, 3)

        XCTAssertEqual(files[0].path, "Docs/Release Notes.md")
        XCTAssertEqual(files[0].kind, .modified)
        XCTAssertEqual(files[0].insertions, 2)
        XCTAssertEqual(files[0].deletions, 1)
        XCTAssertEqual(files[0].hunks.count, 1)
        XCTAssertEqual(files[0].hunks[0].lines.map(\.oldLineNumber), [1, 2, nil, nil, 3])
        XCTAssertEqual(files[0].hunks[0].lines.map(\.newLineNumber), [1, nil, 2, 3, 4])

        XCTAssertEqual(files[1].path, "Sources/New.swift")
        XCTAssertEqual(files[1].oldPath, "Sources/Old.swift")
        XCTAssertEqual(files[1].kind, .renamed)

        XCTAssertEqual(files[2].path, "Assets/logo.png")
        XCTAssertTrue(files[2].isBinary)
    }

    @MainActor
    func testWorkspaceSwitchBranchUpdatesSessionGitMetadataAndReportsConflicts() async throws {
        let fixtureName = "ColumnBranchSwitch-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(fixtureName, isDirectory: true)
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fixtureName).json")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: persistenceURL)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try runGit(arguments: ["-C", directory.path, "init", "-q", "-b", "main"])
        try runGit(arguments: ["-C", directory.path, "config", "user.email", "test@example.com"])
        try runGit(arguments: ["-C", directory.path, "config", "user.name", "Colerm Test"])

        let trackedFile = directory.appendingPathComponent("file.txt")
        try "main content\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(arguments: ["-C", directory.path, "add", "file.txt"])
        try runGit(arguments: ["-C", directory.path, "commit", "-q", "-m", "Initial"])

        try runGit(arguments: ["-C", directory.path, "switch", "-q", "-c", "feature"])
        try "feature content\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(arguments: ["-C", directory.path, "commit", "-q", "-am", "Feature change"])
        try runGit(arguments: ["-C", directory.path, "switch", "-q", "main"])

        let sessionID = UUID()
        let persistence = WorkspacePersistence(fileURL: persistenceURL)
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: sessionID,
                sessions: [
                    PersistedSession(id: sessionID, cwd: directory, columnWidth: 600)
                ]
            )
        )

        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector(cacheLifetime: 60, debounceMilliseconds: 0)
        )
        try await waitForGitBranch(on: store.sessions[0], branch: "main")

        let rawBranches = await store.listBranches(for: sessionID)
        let branches = try XCTUnwrap(rawBranches)
        XCTAssertEqual(branches.localBranches.map(\.name), ["feature", "main"])

        let featureBranch = try XCTUnwrap(branches.localBranches.first { $0.name == "feature" })
        let switchResult = await store.switchBranch(to: featureBranch, for: sessionID)
        XCTAssertNoThrow(try switchResult.get())
        try await waitForGitBranch(on: store.sessions[0], branch: "feature")

        // Create conflicting uncommitted change and verify failure when switching back to main
        try "conflicting dirty change\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        let mainBranch = GitBranch(name: "main", localName: "main", isRemote: false, isCurrent: false)
        let conflictResult = await store.switchBranch(to: mainBranch, for: sessionID)
        if case .success = conflictResult {
            XCTFail("Expected conflicting git switch to fail")
        }
    }

    @MainActor
    func testColumnPagerExtendsRightDiffSidebarBesideTerminalWithoutShrinkingTerminal() async throws {
        let fixtureName = "ColumnDiffSidebar-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(fixtureName, isDirectory: true)
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fixtureName).json")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: persistenceURL)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try runGit(arguments: ["-C", directory.path, "init", "-q", "-b", "main"])
        try runGit(arguments: ["-C", directory.path, "config", "user.email", "test@example.com"])
        try runGit(arguments: ["-C", directory.path, "config", "user.name", "Colerm Test"])

        let trackedFile = directory.appendingPathComponent("tracked.swift")
        try "let value = 1\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(arguments: ["-C", directory.path, "add", "tracked.swift"])
        try runGit(arguments: ["-C", directory.path, "commit", "-q", "-m", "Initial"])

        try "let value = 2\nlet extra = true\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        let untrackedFile = directory.appendingPathComponent("notes.md")
        try "# Notes\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

        let sessionID = UUID()
        let persistence = WorkspacePersistence(fileURL: persistenceURL)
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: sessionID,
                sessions: [
                    PersistedSession(id: sessionID, cwd: directory, columnWidth: 600)
                ]
            )
        )

        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector(cacheLifetime: 60, debounceMilliseconds: 0)
        )
        let suiteName = "ColermAppTests.diffPager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutSettings = KeyboardShortcutSettings(defaults: defaults)

        let pager = ColumnPagerController(
            store: store,
            shortcutSettings: shortcutSettings,
            onOpenSettings: {}
        )
        pager.loadViewIfNeeded()
        pager.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        pager.view.layoutSubtreeIfNeeded()
        pager.synchronize()
        pager.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(pager.columnFrame(for: sessionID)?.width, 600)
        XCTAssertEqual(pager.terminalFrame(for: sessionID)?.width, 600)
        XCTAssertNil(pager.diffSidebarFrame(for: sessionID))

        // Toggle diff sidebar ON
        XCTAssertTrue(store.toggleDiffSidebar(for: sessionID))
        pager.synchronize()
        pager.view.layoutSubtreeIfNeeded()

        let expectedExtendedWidth = 600
            + TerminalSession.diffSidebarDividerWidth
            + TerminalSession.defaultDiffSidebarWidth
        XCTAssertEqual(pager.columnFrame(for: sessionID)?.width, expectedExtendedWidth)
        XCTAssertEqual(pager.terminalFrame(for: sessionID)?.width, 600)
        XCTAssertEqual(
            pager.diffSidebarFrame(for: sessionID)?.origin.x,
            600 + TerminalSession.diffSidebarDividerWidth
        )
        XCTAssertEqual(
            pager.diffSidebarFrame(for: sessionID)?.width,
            TerminalSession.defaultDiffSidebarWidth
        )

        try await waitForDiffFiles(on: store.sessions[0], paths: ["notes.md", "tracked.swift"])

        // Toggle diff sidebar OFF
        XCTAssertFalse(store.toggleDiffSidebar(for: sessionID))
        pager.synchronize()
        pager.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(pager.columnFrame(for: sessionID)?.width, 600)
        XCTAssertEqual(pager.terminalFrame(for: sessionID)?.width, 600)
        XCTAssertNil(pager.diffSidebarFrame(for: sessionID))
    }

    func testTerminalPasteboardPrefersEscapedFileURLOverBareFilenameAndIcon() throws {
        let pasteboard = NSPasteboard(name: .init("ColermTests.fileURL.\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage(width: 4, height: 4)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let fileURL = URL(fileURLWithPath: "/tmp/My Screenshots/shot (1).png")

        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString("shot (1).png", forType: .string)
        item.setData(tiffData, forType: .tiff)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let extracted = TerminalPasteboard.extractPasteText(from: pasteboard)
        XCTAssertEqual(extracted, "/tmp/My\\ Screenshots/shot\\ \\(1\\).png")
    }

    func testTerminalPasteboardPreservesPlainTextEvenWithRichPreviewImage() throws {
        let pasteboard = NSPasteboard(name: .init("ColermTests.richText.\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage(width: 4, height: 4)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)

        let item = NSPasteboardItem()
        item.setString("echo hello\nworld", forType: .string)
        item.setData(tiffData, forType: .tiff)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let extracted = TerminalPasteboard.extractPasteText(from: pasteboard)
        XCTAssertEqual(extracted, "echo hello\nworld")
    }

    func testTerminalPasteboardMaterializesClipboardPNGAndTIFFImagesToReadablePNGPath() throws {
        let imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColermPasteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: imageDirectory) }

        let pasteboard = NSPasteboard(name: .init("ColermTests.image.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage(width: 12, height: 8)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        // 1. Raw PNG screenshot data on clipboard
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(pngData, forType: .png))
        let pngPath = try XCTUnwrap(
            TerminalPasteboard.extractPasteText(from: pasteboard, imageDirectory: imageDirectory)
        )
        XCTAssertTrue(pngPath.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngPath))
        let savedPNGData = try Data(contentsOf: URL(fileURLWithPath: pngPath))
        XCTAssertEqual(savedPNGData, pngData)

        // 2. Raw TIFF image data on clipboard -> transcoded to valid PNG file
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(tiffData, forType: .tiff))
        let convertedPath = try XCTUnwrap(
            TerminalPasteboard.extractPasteText(from: pasteboard, imageDirectory: imageDirectory)
        )
        XCTAssertTrue(convertedPath.hasSuffix(".png"))
        let convertedData = try Data(contentsOf: URL(fileURLWithPath: convertedPath))
        XCTAssertTrue(convertedData.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertNotNil(NSImage(contentsOfFile: convertedPath))
    }

    @MainActor
    func testTerminalSurfaceViewMatchesPasteShortcutAcrossKeyboardLayouts() throws {
        let cmdV = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_V)
        ))
        XCTAssertTrue(TerminalSurfaceView.isPasteKeyEquivalent(cmdV))

        let nonLatinCmdV = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 2,
            windowNumber: 0,
            context: nil,
            characters: "м",
            charactersIgnoringModifiers: "м",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_V)
        ))
        XCTAssertTrue(TerminalSurfaceView.isPasteKeyEquivalent(nonLatinCmdV))

        let ctrlV = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 3,
            windowNumber: 0,
            context: nil,
            characters: "\u{16}",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_V)
        ))
        XCTAssertFalse(TerminalSurfaceView.isPasteKeyEquivalent(ctrlV))
    }

    func testPierreDiffsAssetsResolveBundledHTMLAndBundleJS() throws {
        let indexURL = try XCTUnwrap(PierreDiffsAssets.indexHTMLURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        let bundleURL = indexURL.deletingLastPathComponent().appendingPathComponent("pierre-diffs.js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        let bundleData = try Data(contentsOf: bundleURL)
        XCTAssertGreaterThan(bundleData.count, 100_000)
    }

    @MainActor
    func testPierreDiffsWebViewForbidsRightClickReloadAndKeepsCopyOnly() throws {
        let unselectedMenu = NSMenu()
        let reloadOnly = NSMenuItem(title: "Reload", action: nil, keyEquivalent: "")
        reloadOnly.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierReload")
        unselectedMenu.addItem(reloadOnly)

        PierreDiffsWebView.sanitizeContextMenu(unselectedMenu)
        XCTAssertTrue(unselectedMenu.items.isEmpty)

        let selectedMenu = NSMenu()
        let backItem = NSMenuItem(title: "Back", action: nil, keyEquivalent: "")
        backItem.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierGoBack")
        let reloadItem = NSMenuItem(title: "Reload", action: nil, keyEquivalent: "")
        reloadItem.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierReload")
        let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        copyItem.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierCopy")
        selectedMenu.addItem(backItem)
        selectedMenu.addItem(reloadItem)
        selectedMenu.addItem(.separator())
        selectedMenu.addItem(copyItem)

        PierreDiffsWebView.sanitizeContextMenu(selectedMenu)
        XCTAssertEqual(selectedMenu.items.map(\.title), ["Copy"])

        let webView = PierreDiffsWebView(frame: .zero)
        XCTAssertNil(webView.reload())
        XCTAssertNil(webView.reloadFromOrigin())

        let cmdR = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: "r",
            charactersIgnoringModifiers: "r",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_R)
        ))
        XCTAssertTrue(webView.performKeyEquivalent(with: cmdR))
    }

    func testPierreDiffLayoutStylePersistsAndFallsBackToUnified() {
        let suiteName = "ColermAppTests.diffStyle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(PierreDiffLayoutStyle.persisted(in: defaults), .unified)
        XCTAssertEqual(PierreDiffLayoutStyle.unified.toggled, .split)
        XCTAssertEqual(PierreDiffLayoutStyle.split.toggled, .unified)

        PierreDiffLayoutStyle.split.persist(in: defaults)
        XCTAssertEqual(PierreDiffLayoutStyle.persisted(in: defaults), .split)

        PierreDiffLayoutStyle.unified.persist(in: defaults)
        XCTAssertEqual(PierreDiffLayoutStyle.persisted(in: defaults), .unified)

        defaults.set("invalid", forKey: PierreDiffLayoutStyle.defaultsKey)
        XCTAssertEqual(PierreDiffLayoutStyle.persisted(in: defaults), .unified)
    }

    func testGitDiffParserSubmodulePointerChangeDoesNotInflateLineCounts() {
        let patch = """
        diff --git a/Vendor/ghostty b/Vendor/ghostty
        index 08342c9..08342c9-dirty 160000
        --- a/Vendor/ghostty
        +++ b/Vendor/ghostty
        @@ -1 +1 @@
        -Subproject commit 08342c92446ceda22b49f42ce39e8c4714054a6e
        +Subproject commit 08342c92446ceda22b49f42ce39e8c4714054a6e-dirty
        """

        let files = GitDiffParser.parseUnifiedDiff(patch)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.path, "Vendor/ghostty")
        XCTAssertEqual(files.first?.insertions, 0)
        XCTAssertEqual(files.first?.deletions, 0)
        XCTAssertEqual(files.first?.hunks.first?.lines.count, 2)
    }

    @MainActor
    func testLightTerminalThemeKeepsANSIWhiteReadableAgainstBackground() throws {
        XCTAssertEqual(GhosttySession.lightPalette.count, 16)
        XCTAssertGreaterThanOrEqual(GhosttySession.lightMinimumContrast, 2.5)
        XCTAssertEqual(GhosttySession.lightBackground, "#FAFAFA")
        XCTAssertEqual(GhosttySession.lightPalette[7], "#5C5C5C")
        XCTAssertEqual(GhosttySession.lightPalette[15], "#252525")
        XCTAssertNotEqual(GhosttySession.lightPalette[7], GhosttySession.lightBackground)
        XCTAssertNotEqual(GhosttySession.lightPalette[15], GhosttySession.lightBackground)

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let lightThemeFile = repoRoot.appendingPathComponent("Resources/themes/Colerm Light")
        let themeText = try String(contentsOf: lightThemeFile, encoding: .utf8)
        XCTAssertTrue(themeText.contains("minimum-contrast = 2.5"))
        XCTAssertTrue(themeText.contains("palette = 7=#5C5C5C"))
        XCTAssertTrue(themeText.contains("palette = 15=#252525"))
    }

    func testGitInspectorMetadataMatchesDiffSnapshotTotals() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColumnConsistencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(arguments: ["init", root.path])
        try runGit(arguments: ["-C", root.path, "config", "user.email", "test@example.com"])
        try runGit(arguments: ["-C", root.path, "config", "user.name", "Test User"])

        try "one\ntwo\nthree\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "alpha\nbeta\n".write(to: root.appendingPathComponent("rename-me.txt"), atomically: true, encoding: .utf8)
        try runGit(arguments: ["-C", root.path, "add", "."])
        try runGit(arguments: ["-C", root.path, "commit", "-m", "initial"])

        // Staged + unstaged edit on tracked.txt
        try "one\nTWO\nthree\nfour\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(arguments: ["-C", root.path, "add", "tracked.txt"])
        try "one\nTWO\nthree\nfour\nfive\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        // Rename
        try runGit(arguments: ["-C", root.path, "mv", "rename-me.txt", "renamed.txt"])
        try "alpha\nbeta\ngamma\n".write(to: root.appendingPathComponent("renamed.txt"), atomically: true, encoding: .utf8)

        // Nested untracked directory with multiple files
        let nestedDir = root.appendingPathComponent("nested/sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "a1\na2\n".write(to: nestedDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b1\nb2\nb3\n".write(to: nestedDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let inspector = GitInspector(cacheLifetime: 0, debounceMilliseconds: 0)
        let rawMetadata = await inspector.inspect(directory: root)
        let metadata = try XCTUnwrap(rawMetadata)
        let rawSnapshot = await inspector.inspectDiff(directory: root)
        let snapshot = try XCTUnwrap(rawSnapshot)

        XCTAssertEqual(metadata.changedFiles, snapshot.files.count)
        XCTAssertEqual(metadata.insertions, snapshot.totalInsertions)
        XCTAssertEqual(metadata.deletions, snapshot.totalDeletions)
        XCTAssertEqual(metadata.changedFiles, 4)
        XCTAssertEqual(metadata.insertions, 9)
        XCTAssertEqual(metadata.deletions, 1)
    }

    func testGitInspectorLoadsLargeUntrackedAndImageFileDetailAndRejectsTraversal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColumnDetailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(arguments: ["init", root.path])
        try runGit(arguments: ["-C", root.path, "config", "user.email", "test@example.com"])
        try runGit(arguments: ["-C", root.path, "config", "user.name", "Test User"])

        let largeText = String(repeating: "const value = 42;\n", count: 20_000)
        let largeFileURL = root.appendingPathComponent("bundle.js")
        try largeText.write(to: largeFileURL, atomically: true, encoding: .utf8)

        let image = makeTestImage(width: 6, height: 6)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let pngURL = root.appendingPathComponent("preview.png")
        try pngData.write(to: pngURL)

        let inspector = GitInspector(cacheLifetime: 0, debounceMilliseconds: 0)
        let rawSnapshot = await inspector.inspectDiff(directory: root)
        let snapshot = try XCTUnwrap(rawSnapshot)
        let untrackedBundle = try XCTUnwrap(
            snapshot.untrackedFiles.first { $0.path == "bundle.js" }
        )
        XCTAssertNil(untrackedBundle.contents)
        XCTAssertTrue(untrackedBundle.canLoadDetail)
        XCTAssertTrue(untrackedBundle.note?.hasPrefix("Large untracked file") == true)

        let rawTextDetail = await inspector.loadFileDetail(
            directory: root,
            relativePath: "bundle.js",
            kind: "U"
        )
        let loadedTextDetail = try XCTUnwrap(rawTextDetail)
        XCTAssertEqual(loadedTextDetail.path, "bundle.js")
        XCTAssertEqual(loadedTextDetail.textContents, largeText)
        XCTAssertNil(loadedTextDetail.truncatedNote)
        XCTAssertNil(loadedTextDetail.errorNote)

        let rawImageDetail = await inspector.loadFileDetail(
            directory: root,
            relativePath: "preview.png",
            kind: "U"
        )
        let loadedImageDetail = try XCTUnwrap(rawImageDetail)
        XCTAssertNil(loadedImageDetail.textContents)
        XCTAssertTrue(loadedImageDetail.imageDataURL?.hasPrefix("data:image/png;base64,") == true)

        let traversalAttempt = await inspector.loadFileDetail(
            directory: root,
            relativePath: "../outside.txt",
            kind: "U"
        )
        XCTAssertNil(traversalAttempt)
    }

    func testAgentCommandMatcherRecognizesAllSupportedAgentsAndRejectsFalsePositives() {
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "claude"),
            AgentCommandMatch(agent: .claudeCode, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "claude -p \"fix the login bug\""),
            AgentCommandMatch(agent: .claudeCode, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/opt/homebrew/bin/node",
                arguments: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--continue"]
            ),
            AgentCommandMatch(agent: .claudeCode, startsWorkingImmediately: false)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "npx -y @openai/codex"),
            AgentCommandMatch(agent: .codex, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "codex exec \"run swift test\""),
            AgentCommandMatch(agent: .codex, startsWorkingImmediately: true)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "pi"),
            AgentCommandMatch(agent: .pi, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/Users/dev/.bun/bin/bun",
                arguments: ["bun", "/Users/dev/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/dist/cli.js", "-p", "lint"]
            ),
            AgentCommandMatch(agent: .pi, startsWorkingImmediately: true)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "opencode run \"update docs\""),
            AgentCommandMatch(agent: .opencode, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/Users/dev/.opencode/bin/opencode-darwin-arm64",
                arguments: ["opencode"]
            ),
            AgentCommandMatch(agent: .opencode, startsWorkingImmediately: false)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "grok"),
            AgentCommandMatch(agent: .grok, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/opt/homebrew/bin/node",
                arguments: ["node", "/opt/homebrew/lib/node_modules/@xai-official/grok/dist/index.js"]
            ),
            AgentCommandMatch(agent: .grok, startsWorkingImmediately: false)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "droid exec \"refactor parser\""),
            AgentCommandMatch(agent: .factoryDroid, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "/Users/dev/.factory/bin/droid"),
            AgentCommandMatch(agent: .factoryDroid, startsWorkingImmediately: false)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "cd /tmp/project && FOO=1 caffeinate -i agy"),
            AgentCommandMatch(agent: .agy, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/Users/dev/.gemini/antigravity-cli/bin/agy",
                arguments: ["agy", "-p", "check build"]
            ),
            AgentCommandMatch(agent: .agy, startsWorkingImmediately: true)
        )

        XCTAssertEqual(
            AgentCommandMatcher.match(executablePath: "/Users/dev/.amp/bin/amp", arguments: ["amp", "-x", "fix lint"]),
            AgentCommandMatch(agent: .amp, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/opt/homebrew/bin/node",
                arguments: ["node", "/Users/dev/Library/pnpm/global/5/.pnpm/@google+gemini-cli@0.24.0/node_modules/@google/gemini-cli/dist/index.js"]
            ),
            AgentCommandMatch(agent: .gemini, startsWorkingImmediately: false)
        )
        // Cursor's `agent` wrapper re-execs its bundled node with `exec -a "$0"`.
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/Users/dev/.local/share/cursor-agent/versions/2026.08.11/node",
                arguments: ["/Users/dev/.local/bin/agent", "--use-system-ca", "/Users/dev/.local/share/cursor-agent/versions/2026.08.11/index.js"]
            ),
            AgentCommandMatch(agent: .cursor, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "cursor-agent -p \"summarize\""),
            AgentCommandMatch(agent: .cursor, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/opt/homebrew/bin/node",
                arguments: ["node", "/Users/dev/Library/pnpm/global/5/.pnpm/@github+copilot@0.0.405/node_modules/@github/copilot/npm-loader.js"]
            ),
            AgentCommandMatch(agent: .copilot, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "qwen --prompt \"add tests\""),
            AgentCommandMatch(agent: .qwen, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/Users/dev/.local/share/uv/tools/kimi-cli/bin/python",
                arguments: ["python", "/Users/dev/.local/bin/kimi"]
            ),
            AgentCommandMatch(agent: .kimi, startsWorkingImmediately: false)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "kiro-cli chat --no-interactive \"explain\""),
            AgentCommandMatch(agent: .kiro, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(commandLine: "muse exec \"fix the build\""),
            AgentCommandMatch(agent: .muse, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/Users/dev/.local/bin/muse-bin-1.4.25-R9361.1",
                arguments: ["/Users/dev/.local/bin/muse-bin-1.4.25-R9361.1"]
            ),
            AgentCommandMatch(agent: .muse, startsWorkingImmediately: false)
        )

        // Reject help/version probes and non-agent commands mentioning agent names in arguments
        XCTAssertNil(AgentCommandMatcher.match(commandLine: "claude --version"))
        XCTAssertNil(AgentCommandMatcher.match(commandLine: "agy --help"))
        XCTAssertNil(AgentCommandMatcher.match(commandLine: "vim CLAUDE.md"))
        XCTAssertNil(AgentCommandMatcher.match(commandLine: "rg codex Sources/"))
        XCTAssertNil(AgentCommandMatcher.match(commandLine: "git checkout -b feat/opencode-pi-grok-droid"))
        XCTAssertNil(AgentCommandMatcher.match(commandLine: "node scripts/server.js --agent claude"))
    }

    func testAgentTrackerClearsRunningOnSelectedTabDespiteCursorBlinkAndIgnoresBootMCPNoise() {
        // 1. Reproduce OpenCode boot in background tab (`/update` banner + `1 MCP failed /mcps`):
        //    must stay `.idle` (never falsely enter Running or Done without a prompt).
        var opencodeTracker = AgentActivityTracker()
        let opencodeObs = AgentProcessObservation(
            agent: .opencode,
            rootPID: 700,
            startsWorkingImmediately: false,
            totalCPUNanoseconds: 120_000_000,
            nonAgentChildren: []
        )
        let opencodeBoot1 = TerminalViewportSnapshot.from(lines: [
            "opencode",
            "Ask anything... \"Fix a TODO in the codebase\"",
            "Build · Grok 4.6 OpenRouter"
        ])
        _ = opencodeTracker.poll(
            observation: opencodeObs,
            viewport: opencodeBoot1,
            isTabSelected: false,
            now: 100.0
        )
        XCTAssertEqual(opencodeTracker.status, AgentSessionStatus(agent: .opencode, phase: .idle))

        // 3.5s after launch, async update check + MCP child failure redraws screen and emits boot progress
        var opencodeWithMCP = opencodeObs
        opencodeWithMCP.nonAgentChildren = [
            AgentChildProcessObservation(pid: 701, totalCPUNanoseconds: 8_000_000, isHelperDaemon: true)
        ]
        _ = opencodeTracker.handleProgressReport(.active, isTabSelected: false, now: 103.0)
        let opencodeBoot2 = TerminalViewportSnapshot.from(lines: [
            "opencode",
            "/update to install v2.3.2",
            "Ask anything... \"Fix a TODO in the codebase\"",
            "Build · Grok 4.6 OpenRouter",
            "~/Code/column:master    shift+tab agents",
            "⊙ 1 MCP failed /mcps"
        ])
        _ = opencodeTracker.poll(
            observation: opencodeWithMCP,
            viewport: opencodeBoot2,
            isTabSelected: false,
            now: 103.5
        )
        _ = opencodeTracker.poll(
            observation: opencodeWithMCP,
            viewport: opencodeBoot2,
            isTabSelected: false,
            now: 106.5
        )
        XCTAssertEqual(opencodeTracker.status, AgentSessionStatus(agent: .opencode, phase: .idle))
        XCTAssertEqual(opencodeTracker.status?.isVisibleInTab, false)

        // 2. Reproduce Antigravity (`agy`) in selected Tab 1:
        //    User submits `hi`, AGY replies `Hi! How can I help you with Colerm today?`,
        //    and sits at idle prompt blinking cursor — Running MUST clear to `.idle`.
        var agyTracker = AgentActivityTracker()
        let agyObs = AgentProcessObservation(
            agent: .agy,
            rootPID: 800,
            startsWorkingImmediately: false,
            totalCPUNanoseconds: 90_000_000,
            nonAgentChildren: [
                AgentChildProcessObservation(pid: 801, totalCPUNanoseconds: 20_000_000, isHelperDaemon: true)
            ]
        )
        let agyWelcome = TerminalViewportSnapshot.from(lines: [
            "Antigravity CLI 1.5.11",
            "> Auto mode: edits & safe commands auto-approved (shift+tab to cycle)",
            "? for shortcuts   auto · Gemini 4 Carbon · medium"
        ])
        _ = agyTracker.poll(observation: agyObs, viewport: agyWelcome, isTabSelected: true, now: 200.0)
        XCTAssertEqual(agyTracker.status, AgentSessionStatus(agent: .agy, phase: .idle))

        // User types `hi` and presses Return on selected tab
        _ = agyTracker.handleUserInput(.typing, now: 208.0)
        _ = agyTracker.handleUserInput(.submit, now: 208.3)
        XCTAssertEqual(agyTracker.status, AgentSessionStatus(agent: .agy, phase: .running))

        let agyThinking = TerminalViewportSnapshot.from(lines: [
            "Antigravity CLI 1.5.11",
            "> hi",
            "⠋ Thinking... (esc to cancel)"
        ])
        _ = agyTracker.poll(observation: agyObs, viewport: agyThinking, isTabSelected: true, now: 208.5)
        XCTAssertEqual(agyTracker.status?.phase, .running)

        let agyAnsweredA = TerminalViewportSnapshot.from(lines: [
            "Antigravity CLI 1.5.11",
            "> hi",
            "Hi! How can I help you with Colerm today?",
            "> Auto mode: edits & safe commands auto-approved (shift+tab to cycle)",
            "? for shortcuts   auto · Gemini 4 Carbon · medium"
        ])
        // Even if an ASCII block cursor toggles between 2 frames every 0.5s, ring buffer ignores A<->B blink
        let agyAnsweredBlinkB = TerminalViewportSnapshot.from(lines: [
            "Antigravity CLI 1.5.11",
            "> hi",
            "Hi! How can I help you with Colerm today?",
            "> █uto mode: edits & safe commands auto-approved (shift+tab to cycle)",
            "? for shortcuts   auto · Gemini 4 Carbon · medium"
        ])
        _ = agyTracker.poll(observation: agyObs, viewport: agyAnsweredA, isTabSelected: true, now: 209.0)
        _ = agyTracker.poll(observation: agyObs, viewport: agyAnsweredBlinkB, isTabSelected: true, now: 209.5)
        _ = agyTracker.poll(observation: agyObs, viewport: agyAnsweredA, isTabSelected: true, now: 210.0)
        _ = agyTracker.poll(observation: agyObs, viewport: agyAnsweredBlinkB, isTabSelected: true, now: 210.5)
        _ = agyTracker.poll(observation: agyObs, viewport: agyAnsweredA, isTabSelected: true, now: 211.0)
        _ = agyTracker.poll(observation: agyObs, viewport: agyAnsweredBlinkB, isTabSelected: true, now: 211.6)

        // Selected tab clears Running back to idle automatically!
        XCTAssertEqual(agyTracker.status, AgentSessionStatus(agent: .agy, phase: .idle))
        XCTAssertEqual(agyTracker.status?.isVisibleInTab, false)
    }

    func testAgentTrackerLifecycleHandlesSubmitStreamingSettleAndStaleTitleSpinners() {
        var tracker = AgentActivityTracker()
        let baseObservation = AgentProcessObservation(
            agent: .codex,
            rootPID: 420,
            startsWorkingImmediately: false,
            totalCPUNanoseconds: 100_000_000,
            nonAgentChildren: [
                AgentChildProcessObservation(pid: 421, totalCPUNanoseconds: 5_000_000, isHelperDaemon: true)
            ]
        )
        let idleScreen = TerminalViewportSnapshot.from(lines: ["› Ask Codex to do anything"])

        _ = tracker.poll(observation: baseObservation, viewport: idleScreen, isTabSelected: false, now: 100.5)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .codex, phase: .idle))
        XCTAssertEqual(tracker.status?.isVisibleInTab, false)

        // Empty Enter with prompt redraw reverts back to idle without false "Done"
        _ = tracker.handleUserInput(.submit, now: 107.0)
        XCTAssertEqual(tracker.status?.phase, .running)
        let emptyEcho = TerminalViewportSnapshot.from(lines: ["›", "› Ask Codex to do anything"])
        _ = tracker.poll(observation: baseObservation, viewport: emptyEcho, isTabSelected: false, now: 107.5)
        _ = tracker.poll(observation: baseObservation, viewport: emptyEcho, isTabSelected: false, now: 108.6)
        XCTAssertEqual(tracker.status?.phase, .idle)

        // Typing characters while composing prompt stays idle
        _ = tracker.handleUserInput(.typing, now: 109.0)
        let typingScreen = TerminalViewportSnapshot.from(lines: ["› refactor store"])
        _ = tracker.poll(observation: baseObservation, viewport: typingScreen, isTabSelected: false, now: 109.4)
        XCTAssertEqual(tracker.status?.phase, .idle)

        // Real prompt submission + autonomous TUI streaming + frozen stale spinner title -> Done
        _ = tracker.handleUserInput(.submit, now: 110.0)
        XCTAssertEqual(tracker.status?.phase, .running)

        _ = tracker.handleTitleChange("⠋ Refactoring store", isTabSelected: false, now: 110.3)
        _ = tracker.handleTitleChange("⠙ Refactoring store", isTabSelected: false, now: 110.6)
        _ = tracker.handleTitleChange("⠹ Refactoring store", isTabSelected: false, now: 110.9)

        let workFrame1 = TerminalViewportSnapshot.from(lines: [
            "› refactor store",
            "⠋ Working (1s • esc to interrupt)"
        ])
        let workFrame2 = TerminalViewportSnapshot.from(lines: [
            "› refactor store",
            "Updated WorkspaceStore.swift.",
            "› Ask Codex to do anything"
        ])
        _ = tracker.poll(observation: baseObservation, viewport: workFrame1, isTabSelected: false, now: 111.0)
        XCTAssertEqual(tracker.status?.phase, .running)
        _ = tracker.poll(observation: baseObservation, viewport: workFrame2, isTabSelected: false, now: 112.0)
        XCTAssertEqual(tracker.status?.phase, .running)

        // Output stops at 112.0 while Codex leaves frozen "⠹ Refactoring store" in the title;
        // after passiveSettleInterval (2.0s), background tab transitions to Done.
        _ = tracker.poll(observation: baseObservation, viewport: workFrame2, isTabSelected: false, now: 113.0)
        XCTAssertEqual(tracker.status?.phase, .running)
        _ = tracker.poll(observation: baseObservation, viewport: workFrame2, isTabSelected: false, now: 114.1)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .codex, phase: .done))
        XCTAssertEqual(tracker.status?.isVisibleInTab, true)

        // Switching to the tab clears Done immediately back to idle while TUI remains alive
        XCTAssertTrue(tracker.clearCompletedStatus())
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .codex, phase: .idle))
        XCTAssertEqual(tracker.status?.isVisibleInTab, false)
    }

    @MainActor
    func testWorkspaceStoreClearsCompletedAgentStatusImmediatelyOnTabSelect() throws {
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColumnAgentSelect-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: persistenceURL) }

        let firstID = UUID()
        let secondID = UUID()
        let persistence = WorkspacePersistence(fileURL: persistenceURL)
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: firstID,
                sessions: [
                    PersistedSession(id: firstID, cwd: URL(fileURLWithPath: "/tmp/first"), columnWidth: 600),
                    PersistedSession(id: secondID, cwd: URL(fileURLWithPath: "/tmp/second"), columnWidth: 600)
                ]
            )
        )

        let inspector = MockAgentProcessInspector()
        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector(),
            agentInspector: inspector
        )
        XCTAssertEqual(store.selectedSessionID, firstID)

        // Background tab 2 runs interactive Claude Code -> post-boot progress -> finishes -> Done -> clears on select
        store.sessions[1].commandStarted(commandLine: "claude", now: 10)
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .claudeCode, phase: .idle))

        store.sessions[1].handleProgressReport(.active, now: 18)
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .claudeCode, phase: .running))

        store.sessions[1].handleProgressReport(.remove, now: 20)
        store.handle(.agentStatusHint(secondID, "done"))
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .claudeCode, phase: .done))

        // Selecting tab 2 clears Done immediately back to idle (TUI still open)
        store.select(secondID)
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .claudeCode, phase: .idle))
        XCTAssertEqual(store.sessions[1].agentStatus?.isVisibleInTab, false)

        // Switch back to tab 1; run one-shot `droid exec` in tab 2 which exits with 0 -> Done -> clears to nil on select
        store.select(firstID)
        store.sessions[1].commandStarted(commandLine: "droid exec \"fix tests\"", now: 30)
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .factoryDroid, phase: .running))

        store.handle(.commandFinished(secondID, 0))
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .factoryDroid, phase: .done))

        store.select(secondID)
        XCTAssertNil(store.sessions[1].agentStatus)
    }

    func testAgentViewportAnalyzerAndTrackerDetectAGYQuestionsPermissionsAndIgnoreIdleComposer() {
        var tracker = AgentActivityTracker()
        let agyObservation = AgentProcessObservation(
            agent: .agy,
            rootPID: 910,
            startsWorkingImmediately: false,
            totalCPUNanoseconds: 80_000_000,
            nonAgentChildren: []
        )

        let idleWelcome = TerminalViewportSnapshot.from(lines: [
            "Antigravity CLI",
            "> Auto mode: edits & safe commands auto-approved (shift+tab to cycle)",
            "? for shortcuts   auto · Gemini 4 Argon · medium"
        ])
        _ = tracker.poll(observation: agyObservation, viewport: idleWelcome, isTabSelected: true, now: 100.0)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .agy, phase: .idle))

        // Submit prompt on selected tab -> Running
        _ = tracker.handleUserInput(.typing, now: 107.0)
        _ = tracker.handleUserInput(.submit, now: 107.2)
        XCTAssertEqual(tracker.status?.phase, .running)

        let thinkingScreen = TerminalViewportSnapshot.from(lines: [
            "> remember the selected diff view type and improve design to avoid redundancy of this",
            "⠋ Thinking... (esc to cancel)"
        ])
        _ = tracker.poll(observation: agyObservation, viewport: thinkingScreen, isTabSelected: true, now: 107.5)
        XCTAssertEqual(tracker.status?.phase, .running)

        // AGY renders multi-line wrapped Question 1/1 menu ending with `esc to cancel`:
        // must NOT stay trapped in Running due to `esc to cancel`, and must enter `.needsInput(.question)`.
        let questionChoice1 = TerminalViewportSnapshot.from(lines: [
            "? How would you like to resolve the redundant diff summary between the terminal title bar and the Diffs sidebar header?",
            "Question",
            "────────────────────────────────────────────────────────",
            "Question 1/1: How would you like to resolve the redundant diff summary",
            "between the terminal title bar and the Diffs sidebar header?",
            "> 1. (Recommended) Remove the duplicate counts from the Diffs header",
            "(keep the stats pill in the terminal title bar)",
            "  2. Collapse the terminal title bar button to icon-only when open, and",
            "keep counts in the Diffs header (frees space for branch/path)",
            "  3. Replace \"Diffs 30 +...\" in the sidebar header with a Unified /",
            "Split segmented control",
            "  4. Write-in...",
            "↑/↓ Navigate · enter Select · esc Skip · ctrl+r Review",
            "esc to cancel                 auto · Gemini 4 Argon · medium"
        ])
        XCTAssertEqual(AgentViewportAnalyzer.detectedBlockedKind(in: questionChoice1.tailLines), .question)
        XCTAssertFalse(AgentViewportAnalyzer.hasExplicitBusyIndicator(in: questionChoice1.tailLines))

        _ = tracker.poll(observation: agyObservation, viewport: questionChoice1, isTabSelected: true, now: 108.0)
        _ = tracker.poll(observation: agyObservation, viewport: questionChoice1, isTabSelected: true, now: 108.6)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .agy, phase: .needsInput(.question)))
        XCTAssertEqual(tracker.status?.isVisibleInTab, true)
        XCTAssertEqual(tracker.status?.badgeLabel, "Input")
        XCTAssertEqual(tracker.status?.helpText, "Antigravity · Waiting for Answer")

        // Selecting the tab does NOT clear `.needsInput` (unlike `.done`)
        XCTAssertFalse(tracker.clearCompletedStatus())
        XCTAssertEqual(tracker.status?.phase, .needsInput(.question))

        // Navigating options with ↓ arrow redraws highlight but stays `.needsInput(.question)`
        _ = tracker.handleUserInput(.typing, now: 109.0)
        let questionChoice2 = TerminalViewportSnapshot.from(lines: [
            "Question 1/1: How would you like to resolve the redundant diff summary",
            "  1. (Recommended) Remove the duplicate counts from the Diffs header",
            "> 2. Collapse the terminal title bar button to icon-only when open, and",
            "  3. Replace \"Diffs 30 +...\" in the sidebar header",
            "  4. Write-in...",
            "↑/↓ Navigate · enter Select · esc Skip · ctrl+r Review",
            "esc to cancel                 auto · Gemini 4 Argon · medium"
        ])
        _ = tracker.poll(observation: agyObservation, viewport: questionChoice2, isTabSelected: true, now: 109.5)
        XCTAssertEqual(tracker.status?.phase, .needsInput(.question))

        // Pressing Return (even long after typing, e.g. accepting default choice) immediately resumes `.running`
        _ = tracker.handleUserInput(.submit, now: 145.0)
        XCTAssertEqual(tracker.status?.phase, .running)
        let resumedWork = TerminalViewportSnapshot.from(lines: [
            "● Editing Sources/ColermApp/UI/TerminalDiffSidebarView.swift (esc to cancel)"
        ])
        _ = tracker.poll(observation: agyObservation, viewport: resumedWork, isTabSelected: true, now: 145.5)
        XCTAssertEqual(tracker.status?.phase, .running)

        // Permission prompt detection & Esc dismissal without bounce-back
        let permissionPrompt = TerminalViewportSnapshot.from(lines: [
            "Do you want to proceed?",
            "❯ 1. Yes",
            "  2. Yes, allow for this session",
            "  3. No, and tell the agent what to do differently (esc)",
            "Esc to cancel"
        ])
        XCTAssertEqual(AgentViewportAnalyzer.detectedBlockedKind(in: permissionPrompt.tailLines), .permission)
        _ = tracker.poll(observation: agyObservation, viewport: permissionPrompt, isTabSelected: false, now: 146.0)
        _ = tracker.poll(observation: agyObservation, viewport: permissionPrompt, isTabSelected: false, now: 146.6)
        XCTAssertEqual(tracker.status?.phase, .needsInput(.permission))
        XCTAssertEqual(tracker.status?.badgeLabel, "Approve")

        // Pressing Esc clears `.needsInput` immediately and won't bounce back on the same unchanged screen
        _ = tracker.handleUserInput(.interrupt, now: 147.0)
        XCTAssertEqual(tracker.status?.phase, .idle)
        _ = tracker.poll(observation: agyObservation, viewport: permissionPrompt, isTabSelected: true, now: 147.5)
        XCTAssertEqual(tracker.status?.phase, .idle)

        // Conversation text mentioning permission/question phrases above an idle composer must NOT trigger false positives
        let finishedTurnDiscussingPrompts = TerminalViewportSnapshot.from(lines: [
            "Updated tests for \"Do you want to proceed?\" and \"Question 1/1:\" prompts.",
            "  1. Yes, allow once",
            "  2. Always allow",
            "> Auto mode: edits & safe commands auto-approved (shift+tab to cycle)",
            "? for shortcuts   auto · Gemini 4 Argon · medium"
        ])
        XCTAssertNil(AgentViewportAnalyzer.detectedBlockedKind(in: finishedTurnDiscussingPrompts.tailLines))
        XCTAssertEqual(
            AgentViewportAnalyzer.detectedBlockedKind(in: ["Apply migration now? [y/n]"]),
            .permission
        )
        XCTAssertEqual(
            AgentViewportAnalyzer.detectedBlockedKind(in: ["Open this URL in your browser to authenticate"]),
            .auth
        )
    }

    @MainActor
    func testRexStyleProgramStatusProtocolHintsDesktopNotificationsAndPaletteSearch() throws {
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColumnAgentBlockedHints-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: persistenceURL) }

        let firstID = UUID()
        let secondID = UUID()
        let persistence = WorkspacePersistence(fileURL: persistenceURL)
        try persistence.save(
            PersistedWorkspace(
                selectedSessionID: firstID,
                sessions: [
                    PersistedSession(id: firstID, cwd: URL(fileURLWithPath: "/tmp/app"), columnWidth: 600),
                    PersistedSession(id: secondID, cwd: URL(fileURLWithPath: "/tmp/api"), columnWidth: 600)
                ]
            )
        )

        let store = WorkspaceStore(
            persistence: persistence,
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector(),
            agentInspector: MockAgentProcessInspector()
        )

        // 1. Rex OSC 7501 key-value format over `agentStatusHint`
        store.handle(.agentStatusHint(secondID, "state=working:app=claude-code"))
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .claudeCode, phase: .running))

        store.handle(.agentStatusHint(secondID, "state=blocked:kind=permission:app=claude-code:msg=QmFzaA=="))
        XCTAssertEqual(
            store.sessions[1].agentStatus,
            AgentSessionStatus(agent: .claudeCode, phase: .needsInput(.permission))
        )
        XCTAssertEqual(store.sessions[1].agentStatus?.badgeLabel, "Approve")
        XCTAssertEqual(store.sessions[1].agentStatus?.helpText, "Claude Code · Waiting for Approval")

        // Selecting a blocked tab preserves the blocked badge until resolved
        store.select(secondID)
        XCTAssertEqual(
            store.sessions[1].agentStatus,
            AgentSessionStatus(agent: .claudeCode, phase: .needsInput(.permission))
        )

        store.select(firstID)
        store.handle(.agentStatusHint(secondID, "state=done:app=claude-code"))
        XCTAssertEqual(store.sessions[1].agentStatus, AgentSessionStatus(agent: .claudeCode, phase: .done))

        // 2. Native OSC 9/777 desktop notification from a live agent session surfaces `.needsInput`
        store.sessions[0].commandStarted(commandLine: "codex", now: 50)
        store.sessions[0].handleAgentDesktopNotification(
            title: "Codex",
            body: "Codex is waiting for your input",
            now: 55
        )
        XCTAssertEqual(
            store.sessions[0].agentStatus,
            AgentSessionStatus(agent: .codex, phase: .needsInput(.input))
        )

        // 3. Command palette search matches agent status badges ("approve", "input")
        let paletteItems = [
            TerminalPaletteItem(
                id: firstID,
                index: 1,
                title: "app",
                path: "/tmp/app",
                agentStatus: store.sessions[0].agentStatus
            ),
            TerminalPaletteItem(
                id: secondID,
                index: 2,
                title: "api",
                path: "/tmp/api",
                agentStatus: AgentSessionStatus(agent: .claudeCode, phase: .needsInput(.permission))
            )
        ]
        XCTAssertEqual(TerminalPaletteSearch.filter(paletteItems, query: "approve").map(\.id), [secondID])
        XCTAssertEqual(TerminalPaletteSearch.filter(paletteItems, query: "codex input").map(\.id), [firstID])
    }

    @MainActor
    func testTerminalSurfaceViewClassifiesReturnInterruptAndModifiedReturnKeys() throws {
        let plainReturn = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: UInt16(kVK_Return)
        ))
        let shiftReturn = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: UInt16(kVK_Return)
        ))
        let escapeKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))
        let letterKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_A)
        ))

        XCTAssertEqual(TerminalSurfaceView.classifyKeyInput(plainReturn), .submit)
        XCTAssertEqual(TerminalSurfaceView.classifyKeyInput(shiftReturn), .typing)
        XCTAssertEqual(TerminalSurfaceView.classifyKeyInput(escapeKey), .interrupt)
        XCTAssertEqual(TerminalSurfaceView.classifyKeyInput(letterKey), .typing)

        let systemInspector = SystemAgentProcessInspector()
        XCTAssertNil(systemInspector.inspect(foregroundPID: getpid()))
    }

    @MainActor
    func testGhosttySessionReadsLiveViewportTextFromAttachedSurface() async throws {
        let runtime = GhosttyRuntime()
        runtime.start()

        let session = runtime.createSession(
            options: SessionLaunchOptions(
                command: "/bin/echo COLERM_VIEWPORT_OK && /bin/sleep 2"
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            runtime.destroySession(session)
            runtime.stop()
            window.orderOut(nil)
        }

        session.view.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        window.contentView = session.view
        window.layoutIfNeeded()
        session.view.layoutSubtreeIfNeeded()

        var foundMarker = false
        var lastSnapshot: TerminalViewportSnapshot?
        for _ in 0 ..< 40 {
            if let snapshot = session.pollViewportSnapshot(readText: true) {
                lastSnapshot = snapshot
                if snapshot.tailLines.contains(where: { $0.contains("COLERM_VIEWPORT_OK") }) {
                    foundMarker = true
                    break
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(
            foundMarker,
            "Expected live GhosttySession viewport snapshot to read rendered output, got \(String(describing: lastSnapshot)) isRunning=\(session.isRunning) pid=\(String(describing: session.foregroundPID))"
        )
    }

    @MainActor
    func testGhosttySessionReadsActiveScreenUnaffectedByScrollbackPosition() async throws {
        let runtime = GhosttyRuntime()
        runtime.start()

        let session = runtime.createSession(
            options: SessionLaunchOptions(
                command: "/bin/sh -c 'i=1; while [ $i -le 60 ]; do echo \"HIST_LINE_$i esc to interrupt\"; i=$((i+1)); done; echo ACTIVE_BOTTOM_OK; sleep 3'"
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            runtime.destroySession(session)
            runtime.stop()
            window.orderOut(nil)
        }

        session.view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        window.contentView = session.view
        window.layoutIfNeeded()
        session.view.layoutSubtreeIfNeeded()

        var bottomSnapshot: TerminalViewportSnapshot?
        for _ in 0 ..< 50 {
            if let snapshot = session.pollViewportSnapshot(readText: true),
               snapshot.tailLines.contains(where: { $0.contains("ACTIVE_BOTTOM_OK") }) {
                bottomSnapshot = snapshot
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let initialSnapshot = try XCTUnwrap(bottomSnapshot)

        // Scroll viewport all the way up into scrollback history
        _ = session.terminalView.performBindingAction("scroll_to_top")
        try await Task.sleep(nanoseconds: 100_000_000)

        let afterScrollSnapshot = try XCTUnwrap(session.pollViewportSnapshot(readText: true))
        XCTAssertTrue(
            afterScrollSnapshot.tailLines.contains(where: { $0.contains("ACTIVE_BOTTOM_OK") }),
            "Expected GHOSTTY_POINT_ACTIVE snapshot to remain on active screen after scrolling up, got \(afterScrollSnapshot.tailLines)"
        )
        XCTAssertEqual(
            afterScrollSnapshot.contentHash,
            initialSnapshot.contentHash,
            "Scrolling Ghostty scrollback must not change the active-screen contentHash"
        )
    }

    func testManualScrollingAndBareScreenChangesInFinishedSessionNeverTriggerRunning() {
        var tracker = AgentActivityTracker()
        let obs = AgentProcessObservation(
            agent: .claudeCode,
            rootPID: 1200,
            startsWorkingImmediately: false,
            totalCPUNanoseconds: 100_000_000,
            nonAgentChildren: []
        )
        let idleScreen = TerminalViewportSnapshot.from(lines: [
            "Finished refactoring the store.",
            "> Try \"refactor WorkspaceStore\"",
            "? for shortcuts"
        ])

        _ = tracker.poll(observation: obs, viewport: idleScreen, isTabSelected: true, now: 100.0)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .idle))

        // 1. User scrolls inside a mouse-captured TUI past historical output — including old
        //    "esc to interrupt" banners and old permission dialogs — must remain `.idle`.
        let scrolledFrames: [TerminalViewportSnapshot] = [
            TerminalViewportSnapshot.from(lines: ["Earlier output line 1", "Earlier output line 2"]),
            TerminalViewportSnapshot.from(lines: ["Earlier tool output", "Working... (esc to interrupt)"]),
            TerminalViewportSnapshot.from(lines: [
                "Do you want to proceed?",
                "❯ 1. Yes",
                "  2. Always allow",
                "Esc to cancel"
            ]),
            TerminalViewportSnapshot.from(lines: ["Older transcript block A", "Older transcript block B"]),
            TerminalViewportSnapshot.from(lines: ["Older transcript block C", "Older transcript block D"]),
            TerminalViewportSnapshot.from(lines: ["Older transcript block E", "Older transcript block F"])
        ]

        var timestamp = 110.0
        for frame in scrolledFrames {
            _ = tracker.handleUserInput(.interaction, now: timestamp)
            _ = tracker.poll(observation: obs, viewport: frame, isTabSelected: true, now: timestamp + 0.5)
            XCTAssertEqual(
                tracker.status,
                AgentSessionStatus(agent: .claudeCode, phase: .idle),
                "Scrolling a finished session must never report Running or Blocked"
            )
            timestamp += 0.5
        }

        // 2. Even without interaction events (e.g. a TUI statusline clock or resize reflow),
        //    bare novel screen diffs without a positive work signal must NOT promote idle -> running.
        for step in 0 ..< 8 {
            let tickTime = timestamp + 5.0 + Double(step) * 0.5
            let frame = TerminalViewportSnapshot.from(lines: [
                "Idle transcript frame \(step)",
                "? for shortcuts   12:0\(step)"
            ])
            _ = tracker.poll(observation: obs, viewport: frame, isTabSelected: true, now: tickTime)
            XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .idle))
        }
    }

    func testAuthoritativeHooksDriveDeterministicLifecycleAndResistTimeoutsAndScrolling() {
        var tracker = AgentActivityTracker()
        let claudeObs = AgentProcessObservation(
            agent: .claudeCode,
            rootPID: 2300,
            startsWorkingImmediately: false,
            totalCPUNanoseconds: 120_000_000,
            nonAgentChildren: []
        )
        let idleScreen = TerminalViewportSnapshot.from(lines: [
            ">",
            "? for shortcuts"
        ])

        _ = tracker.poll(observation: claudeObs, viewport: idleScreen, isTabSelected: false, now: 100.0)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .idle))

        // Authoritative hook: UserPromptSubmit -> Running
        _ = tracker.handleExplicitHint(
            "state=working:app=claude-code:auth=1",
            isTabSelected: false,
            now: 110.0
        )
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .running))

        // Long silent 30-second LLM thinking wait with unchanged screen must STAY Running
        // (never prematurely settle to Done after passiveSettleInterval).
        _ = tracker.poll(observation: claudeObs, viewport: idleScreen, isTabSelected: false, now: 120.0)
        _ = tracker.poll(observation: claudeObs, viewport: idleScreen, isTabSelected: false, now: 140.0)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .running))

        // Authoritative PermissionRequest -> Approve
        _ = tracker.handleExplicitHint(
            "state=blocked:kind=permission:app=claude-code:auth=1",
            isTabSelected: false,
            now: 141.0
        )
        XCTAssertEqual(
            tracker.status,
            AgentSessionStatus(agent: .claudeCode, phase: .needsInput(.permission))
        )

        // Approving via Enter immediately resumes Running (even before PostToolUse returns)
        _ = tracker.handleUserInput(.submit, now: 145.0)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .running))

        // Authoritative Stop on background tab -> Done
        _ = tracker.handleExplicitHint(
            "state=done:app=claude-code:auth=1",
            isTabSelected: false,
            now: 155.0
        )
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .done))

        // Selecting tab clears Done -> Idle; empty Enter, title spinners, or scrolling must NOT flip Running
        XCTAssertTrue(tracker.clearCompletedStatus())
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .idle))

        _ = tracker.handleUserInput(.submit, now: 160.0)
        _ = tracker.handleTitleChange("⠋ Stale", isTabSelected: true, now: 160.2)
        _ = tracker.handleTitleChange("⠙ Stale", isTabSelected: true, now: 160.4)
        _ = tracker.handleTitleChange("⠹ Stale", isTabSelected: true, now: 160.6)
        let busyScrollbackFrame = TerminalViewportSnapshot.from(lines: [
            "Old working line (esc to interrupt)"
        ])
        _ = tracker.poll(observation: claudeObs, viewport: busyScrollbackFrame, isTabSelected: true, now: 161.0)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .idle))

        // Esc interrupt safety net: if UserPromptSubmit runs and user presses Esc without Stop firing,
        // seeing the idle composer after passiveSettleInterval recovers cleanly to `.idle`.
        _ = tracker.handleExplicitHint(
            "state=working:app=claude-code:auth=1",
            isTabSelected: true,
            now: 170.0
        )
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .running))
        _ = tracker.handleUserInput(.interrupt, now: 171.0)
        _ = tracker.poll(observation: claudeObs, viewport: idleScreen, isTabSelected: true, now: 173.5)
        XCTAssertEqual(tracker.status, AgentSessionStatus(agent: .claudeCode, phase: .idle))
    }

    @MainActor
    func testCommandMatcherAndNavigationKeysAndHintParserAuthFlag() throws {
        // Wrapper-injected `-c notify=...` before `exec` still detects Codex immediate work
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/usr/local/bin/codex",
                arguments: ["codex", "-c", "notify=[\"/tmp/hook\",\"codex\",\"notify\"]", "exec", "fix tests"]
            ),
            AgentCommandMatch(agent: .codex, startsWorkingImmediately: true)
        )
        XCTAssertEqual(
            AgentCommandMatcher.match(
                executablePath: "/usr/local/bin/claude",
                arguments: ["claude", "--settings", "/tmp/colerm-claude-hooks.json"]
            ),
            AgentCommandMatch(agent: .claudeCode, startsWorkingImmediately: false)
        )

        // Authoritative flag parsed from Rex-style key-value hint
        let authHint = AgentStatusHintParser.parse("state=working:app=claude-code:auth=1")
        XCTAssertEqual(
            authHint,
            ParsedAgentStatusHint(action: .running, agent: .claudeCode, authoritative: true)
        )
        let nonAuthHint = AgentStatusHintParser.parse("state=done:app=codex")
        XCTAssertEqual(
            nonAuthHint,
            ParsedAgentStatusHint(action: .done, agent: .codex, authoritative: false)
        )

        // PageUp / PageDown classify as `.interaction` rather than `.typing`
        let pageUp = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F72C}",
            charactersIgnoringModifiers: "\u{F72C}",
            isARepeat: false,
            keyCode: UInt16(kVK_PageUp)
        ))
        XCTAssertEqual(TerminalSurfaceView.classifyKeyInput(pageUp), .interaction)
    }

    @MainActor
    func testAgentStatusEventChannelReceivesHookScriptEventsAndValidatesBundledHooksJSON() async throws {
        // 1. Validate bundled Claude hooks JSON parses cleanly
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hooksJSONURL = rootURL.appendingPathComponent(
            "Resources/shell-integration/zsh/colerm-claude-hooks.json"
        )
        let hookScriptURL = rootURL.appendingPathComponent(
            "Resources/shell-integration/zsh/colerm-agent-hook.sh"
        )
        let jsonData = try Data(contentsOf: hooksJSONURL)
        let parsedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        )
        let hooksDict = try XCTUnwrap(parsedJSON["hooks"] as? [String: Any])
        XCTAssertNotNil(hooksDict["UserPromptSubmit"])
        XCTAssertNotNil(hooksDict["PreToolUse"])
        XCTAssertNotNil(hooksDict["PostToolUse"])
        XCTAssertNotNil(hooksDict["PermissionRequest"])
        XCTAssertNotNil(hooksDict["Notification"])
        XCTAssertNotNil(hooksDict["Stop"])
        XCTAssertNotNil(hooksDict["SessionEnd"])

        // 2. Start live event channel and invoke `colerm-agent-hook.sh` end-to-end
        let expectedSessionID = UUID()
        var receivedEvents: [(TerminalSessionID, String)] = []
        let statusDir = "/tmp/colerm-test-\(String(UUID().uuidString.prefix(8)).lowercased())"
        let channel = try XCTUnwrap(
            AgentStatusEventChannel(directoryPath: statusDir) { sessionID, hint in
                receivedEvents.append((sessionID, hint))
            }
        )
        defer { channel.stop() }

        let runHook: ([String], String?) throws -> Void = { args, stdinText in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = [hookScriptURL.path] + args
            proc.environment = [
                "PATH": "/usr/bin:/bin",
                "COLERM_STATUS_DIR": channel.directoryPath,
                "COLERM_SESSION_ID": expectedSessionID.uuidString
            ]
            if let stdinText {
                let pipe = Pipe()
                proc.standardInput = pipe
                try proc.run()
                pipe.fileHandleForWriting.write(Data(stdinText.utf8))
                try pipe.fileHandleForWriting.close()
            } else {
                proc.standardInput = FileHandle.nullDevice
                try proc.run()
            }
            proc.waitUntilExit()
            XCTAssertEqual(proc.terminationStatus, 0)
        }

        try runHook(["claude", "UserPromptSubmit"], nil)
        try runHook(["claude", "PreToolUse"], "{\"tool_name\":\"AskUserQuestion\"}")
        try runHook(["claude", "Stop"], nil)
        try runHook(["codex", "notify", "{\"type\":\"agent-turn-complete\"}"], nil)

        for _ in 0 ..< 40 where receivedEvents.count < 4 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(receivedEvents.count, 4)
        guard receivedEvents.count == 4 else { return }
        XCTAssertEqual(receivedEvents[0].0, expectedSessionID)
        XCTAssertEqual(receivedEvents[0].1, "state=working:app=claude-code:auth=1")
        XCTAssertEqual(receivedEvents[1].1, "state=blocked:kind=question:app=claude-code:auth=1")
        XCTAssertEqual(receivedEvents[2].1, "state=done:app=claude-code:auth=1")
        XCTAssertEqual(receivedEvents[3].1, "state=done:app=codex")

        // Stopping the channel removes the temp directory so future hook calls become no-ops
        channel.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: statusDir))
    }
}

@MainActor
private final class KeyDownRecordingTextView: NSTextView {
    private(set) var keyDownCallCount = 0

    override func keyDown(with event: NSEvent) {
        keyDownCallCount += 1
    }
}

private func runGit(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
}

@MainActor
private func waitForGitStatus(
    on session: TerminalSession,
    changedFiles: Int
) async throws {
    for _ in 0..<20 {
        if session.metadata.git?.changedFiles == changedFiles {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("Timed out waiting for Git status with \(changedFiles) changed files")
}

@MainActor
private func waitForGitBranch(
    on session: TerminalSession,
    branch: String
) async throws {
    for _ in 0..<30 {
        if session.metadata.git?.branch == branch {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("Timed out waiting for Git branch \(branch), got \(session.metadata.git?.branch ?? "nil")")
}

@MainActor
private func waitForDiffFiles(
    on session: TerminalSession,
    paths: [String]
) async throws {
    for _ in 0..<30 {
        if session.diffSnapshot?.files.map(\.path) == paths {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("Timed out waiting for diff files \(paths), got \(session.diffSnapshot?.files.map(\.path) ?? [])")
}

private func makeTestImage(width: Int, height: Int) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(rep)
    return image
}

@MainActor
private final class ActivityTestEngine: TerminalEngineSession {
    let view = NSView(frame: .zero)
    var reportedForegroundPID: pid_t?
    var foregroundPID: pid_t? { reportedForegroundPID }
    var isRunning = true

    func focus() {}
    func blur() {}
    func setOccluded(_: Bool) {}
    func close() { isRunning = false }
}

@MainActor
private final class MockAgentProcessInspector: AgentProcessInspecting {
    var observation: AgentProcessObservation?

    func inspect(foregroundPID _: pid_t) -> AgentProcessObservation? {
        observation
    }
}
