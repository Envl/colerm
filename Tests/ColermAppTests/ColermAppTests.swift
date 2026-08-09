import XCTest
import AppKit
import Carbon
@testable import ColermApp

final class ColermAppTests: XCTestCase {
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
        XCTAssertEqual(ColermTheme.ghosttyTheme, "light:Colerm Light,dark:Colerm Dark")
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
