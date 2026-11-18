import AppKit
import GhosttyKit
import GhosttyTerminal

@MainActor
final class GhosttySession: TerminalEngineSession {
    let id: UUID
    let terminalView: TerminalSurfaceView

    private let controller: TerminalController
    private let actionHandler: (GhosttyAction) -> Void
    private weak var attachedSurface: TerminalSurface?
    private var isClosed = false
    private var hasSurface = false

    var view: NSView { terminalView }
    var foregroundPID: pid_t? { terminalView.foregroundPid }
    var ttyName: String? { terminalView.ttyName }
    var isRunning: Bool {
        !isClosed && hasSurface && foregroundPID != nil
    }

    init(
        id: UUID,
        options: SessionLaunchOptions,
        actionHandler: @escaping (GhosttyAction) -> Void
    ) {
        self.id = id
        self.actionHandler = actionHandler

        var configuration = TerminalConfiguration.default
            .custom("confirm-close-surface", "true")
            .custom("shell-integration", "detect")
            .custom("term", "xterm-256color")
            .custom("window-padding-x", "10")
        if let command = options.command, !command.isEmpty {
            configuration = configuration.custom("command", "shell:\(command)")
        }
        controller = TerminalController(
            configuration: configuration,
            theme: Self.terminalTheme
        )

        terminalView = TerminalSurfaceView(frame: .zero)
        terminalView.configuration = TerminalSurfaceOptions(
            workingDirectory: options.workingDirectory?.path,
            envVars: options.environment.merging(
                ["COLERM_SESSION_ID": id.uuidString],
                uniquingKeysWith: { current, _ in current }
            ),
            context: .window
        )
        terminalView.delegate = self
        terminalView.controller = controller
        terminalView.onLayout = { [weak self] in
            self?.ensureSurface()
        }
        terminalView.onUserInput = { [weak self] inputKind in
            guard let self else { return }
            self.actionHandler(.userInput(self.id, inputKind))
        }
    }

    func focus() {
        guard terminalView.window?.firstResponder !== terminalView else { return }
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func blur() {
        guard terminalView.window?.firstResponder === terminalView else { return }
        terminalView.window?.makeFirstResponder(nil)
    }

    func setOccluded(_ occluded: Bool) {
        terminalView.setSurfaceVisible(!occluded)
    }

    func pollViewportSnapshot(readText: Bool) -> TerminalViewportSnapshot? {
        guard !isClosed else { return nil }
        controller.tick()
        guard readText,
              hasSurface,
              let attachedSurface,
              let rawSurface = Self.extractRawSurface(from: attachedSurface)
        else {
            return nil
        }

        let size = ghostty_surface_size(rawSurface)
        guard size.columns > 0, size.rows > 0 else { return nil }

        var rawLines: [String] = []
        rawLines.reserveCapacity(Int(size.rows))

        for row in 0 ..< UInt32(size.rows) {
            let selection = ghostty_selection_s(
                top_left: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_EXACT,
                    x: 0,
                    y: row
                ),
                bottom_right: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_EXACT,
                    x: UInt32(size.columns) - 1,
                    y: row
                ),
                rectangle: false
            )
            var out = ghostty_text_s()
            guard ghostty_surface_read_text(rawSurface, selection, &out) else {
                continue
            }
            defer { ghostty_surface_free_text(rawSurface, &out) }
            guard let textPtr = out.text, out.text_len > 0 else {
                continue
            }
            let bytes = UnsafeBufferPointer(start: textPtr, count: Int(out.text_len))
                .map { UInt8(bitPattern: $0) }
            rawLines.append(String(decoding: bytes, as: UTF8.self))
        }

        return TerminalViewportSnapshot.from(lines: rawLines)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        attachedSurface = nil
        terminalView.controller = nil
        terminalView.delegate = nil
        terminalView.onLayout = nil
        terminalView.onUserInput = nil
    }

    static let lightBackground = "#FAFAFA"
    static let lightForeground = "#252525"
    static let lightMinimumContrast = 2.5
    static let lightPalette: [String] = [
        "#252525",
        "#B73030",
        "#527A20",
        "#9A6500",
        "#326B9A",
        "#8B3F78",
        "#187A76",
        "#5C5C5C",
        "#686868",
        "#D04444",
        "#67962D",
        "#B77B10",
        "#477FAE",
        "#A65391",
        "#278F8A",
        "#252525"
    ]

    static let terminalTheme = TerminalTheme(
        light: TerminalConfiguration { builder in
            builder.withBackground(lightBackground)
            builder.withForeground(lightForeground)
            builder.withCursorColor("#202020")
            builder.withCursorText("#FAFAFA")
            builder.withSelectionBackground("#B7D7E8")
            builder.withSelectionForeground("#101010")
            builder.withMinimumContrast(lightMinimumContrast)
            for (index, color) in lightPalette.enumerated() {
                builder.withPalette(index, color: color)
            }
        },
        dark: TerminalConfiguration { builder in
            builder.withBackground("#202020")
            builder.withForeground("#D4D4D4")
            builder.withCursorColor("#E8E8E8")
            builder.withCursorText("#202020")
            builder.withSelectionBackground("#3E6480")
            builder.withSelectionForeground("#FFFFFF")
            builder.withPalette(0, color: "#202020")
            builder.withPalette(1, color: "#D44A4A")
            builder.withPalette(2, color: "#8FA84F")
            builder.withPalette(3, color: "#E5B95C")
            builder.withPalette(4, color: "#70A7CC")
            builder.withPalette(5, color: "#B45A9B")
            builder.withPalette(6, color: "#73D2CD")
            builder.withPalette(7, color: "#D4D4D4")
            builder.withPalette(8, color: "#666666")
            builder.withPalette(9, color: "#E35D5D")
            builder.withPalette(10, color: "#A7BF67")
            builder.withPalette(11, color: "#F0C66E")
            builder.withPalette(12, color: "#89BFE3")
            builder.withPalette(13, color: "#CC73B2")
            builder.withPalette(14, color: "#8BE3DE")
            builder.withPalette(15, color: "#F2F2F2")
        }
    )
}

extension GhosttySession:
    TerminalSurfaceTitleDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceProgressReportDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceLifecycleDelegate,
    TerminalSurfaceOpenURLDelegate
{
    func terminalDidAttachSurface(_ surface: TerminalSurface) {
        hasSurface = true
        attachedSurface = surface
    }

    func terminalDidDetachSurface() {
        hasSurface = false
        attachedSurface = nil
    }

    func terminalDidChangeTitle(_ title: String) {
        actionHandler(.title(id, title))
    }

    func terminalDidChangeWorkingDirectory(_ path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        actionHandler(.workingDirectory(id, url))
    }

    func terminalDidFinishCommand(exitCode: Int?, durationNanos _: UInt64) {
        actionHandler(.commandFinished(id, exitCode.map(Int32.init)))
    }

    func terminalDidReportProgress(state: TerminalProgressState, percent _: Int?) {
        let mapped: GhosttyProgressState
        switch state {
        case .remove:
            mapped = .remove
        case .set, .indeterminate:
            mapped = .active
        case .pause:
            mapped = .pause
        case .error:
            mapped = .error
        }
        actionHandler(.progressReport(id, mapped))
    }

    func terminalDidRequestDesktopNotification(title: String, body: String) {
        if title == "colerm", body.hasPrefix("1:") {
            actionHandler(.columnMetadata(id, String(body.dropFirst(2))))
        } else if title == "colerm", body.hasPrefix("2:") {
            let encoded = String(body.dropFirst(2))
            let commandLine = Self.decodeCommandLineBase64(encoded)
            actionHandler(.commandStarted(id, commandLine: commandLine))
        } else if title == "colerm", body.hasPrefix("3:") {
            actionHandler(.agentStatusHint(id, String(body.dropFirst(2))))
        } else if title == "7501" {
            actionHandler(.agentStatusHint(id, body))
        } else {
            actionHandler(.desktopNotification(id, title: title, body: body))
        }
    }

    private static func decodeCommandLineBase64(_ encoded: String) -> String? {
        guard !encoded.isEmpty,
              encoded.utf8.count <= 2048,
              let data = Data(base64Encoded: encoded),
              let decoded = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let cleaned = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    func terminalDidRingBell() {
        actionHandler(.ringBell(id))
    }

    func terminalDidClose(processAlive: Bool) {
        actionHandler(.surfaceClosed(id, processAlive: processAlive))
    }

    func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        guard let url = URL(string: url) else { return }
        actionHandler(.openURL(url))
    }

    private func ensureSurface() {
        guard !isClosed,
              !hasSurface,
              terminalView.window != nil,
              terminalView.bounds.width > 0,
              terminalView.bounds.height > 0
        else { return }

        // Ghostty can attach the view before AppKit has assigned its final frame.
        // Retry the normal controller lifecycle once layout provides a usable size.
        terminalView.controller = nil
        terminalView.controller = controller
    }

    private static func extractRawSurface(from terminalSurface: TerminalSurface) -> ghostty_surface_t? {
        var hasBeenFreed = false
        var foundSurface: ghostty_surface_t?

        for child in Mirror(reflecting: terminalSurface).children {
            if child.label == "hasBeenFreed", let freed = child.value as? Bool {
                hasBeenFreed = freed
            } else if child.label == "surface" {
                let optMirror = Mirror(reflecting: child.value)
                if optMirror.displayStyle == .optional,
                   let unwrapped = optMirror.children.first,
                   let pointer = unwrapped.value as? ghostty_surface_t {
                    foundSurface = pointer
                } else if let pointer = child.value as? ghostty_surface_t {
                    foundSurface = pointer
                }
            }
        }

        return hasBeenFreed ? nil : foundSurface
    }
}
