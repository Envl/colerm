import AppKit

enum GhosttyRuntimeStatus: Equatable {
    case stopped
    case ready
    case unavailable(String)

    var summary: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .ready:
            return "Ready"
        case .unavailable(let reason):
            return reason
        }
    }
}

struct SessionLaunchOptions: Equatable {
    var workingDirectory: URL?
    var command: String?
    var environment: [String: String]

    init(
        workingDirectory: URL? = nil,
        command: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
    }
}

@MainActor
protocol TerminalEngineSession: AnyObject {
    var view: NSView { get }
    var foregroundPID: pid_t? { get }
    var isRunning: Bool { get }

    func focus()
    func blur()
    func setOccluded(_ occluded: Bool)
    func close()
}

extension TerminalEngineSession {
    var foregroundPID: pid_t? { nil }
    var isRunning: Bool { true }
}
