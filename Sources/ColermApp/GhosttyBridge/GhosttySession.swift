import AppKit
import GhosttyTerminal

@MainActor
final class GhosttySession: TerminalEngineSession {
    let id: UUID
    let terminalView: TerminalSurfaceView

    private let controller: TerminalController
    private let actionHandler: (GhosttyAction) -> Void
    private(set) var isRunning = true

    var view: NSView { terminalView }
    var foregroundPID: pid_t? { terminalView.foregroundPid }

    init(
        id: UUID,
        options: SessionLaunchOptions,
        actionHandler: @escaping (GhosttyAction) -> Void
    ) {
        self.id = id
        self.actionHandler = actionHandler

        var configuration = TerminalConfiguration.default
            .custom("confirm-close-surface", "false")
            .custom("shell-integration", "detect")
            .custom("term", "xterm-256color")
            .custom("theme", ColermTheme.ghosttyTheme)
            .custom("window-padding-x", "6")
        if let command = options.command, !command.isEmpty {
            configuration = configuration.custom("command", "shell:\(command)")
        }
        controller = TerminalController(configuration: configuration)

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

    func close() {
        guard isRunning else { return }
        isRunning = false
        terminalView.controller = nil
        terminalView.delegate = nil
    }
}

extension GhosttySession:
    TerminalSurfaceTitleDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceOpenURLDelegate
{
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

    func terminalDidRequestDesktopNotification(title: String, body: String) {
        if title == "colerm", body.hasPrefix("1:") {
            actionHandler(.columnMetadata(id, String(body.dropFirst(2))))
        } else {
            actionHandler(.desktopNotification(title: title, body: body))
        }
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
}
