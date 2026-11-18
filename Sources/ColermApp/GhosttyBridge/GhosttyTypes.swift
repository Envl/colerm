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

enum TerminalUserInputKind: Equatable, Sendable {
    case submit
    case typing
    case interrupt
}

enum GhosttyProgressState: Equatable, Sendable {
    case remove
    case active
    case pause
    case error
}

struct TerminalViewportSnapshot: Equatable, Sendable {
    var tailLines: [String]
    var contentHash: UInt64

    static func from(lines rawLines: [String], maxTailLines: Int = 12) -> TerminalViewportSnapshot {
        var nonEmpty: [String] = []
        nonEmpty.reserveCapacity(rawLines.count)
        var hash: UInt64 = 0xcbf29ce484222325

        for rawLine in rawLines {
            let trimmed = trimTrailingWhitespace(rawLine)
            guard !trimmed.isEmpty else { continue }
            nonEmpty.append(trimmed)
            for byte in trimmed.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
            hash ^= 0x0a
            hash &*= 0x100000001b3
        }

        let tail = Array(nonEmpty.suffix(max(maxTailLines, 0)))
        return TerminalViewportSnapshot(tailLines: tail, contentHash: hash)
    }

    private static func trimTrailingWhitespace(_ value: String) -> String {
        var sub = Substring(value)
        while let last = sub.last, last == " " || last == "\t" || last == "\r" {
            sub = sub.dropLast()
        }
        return String(sub)
    }
}

@MainActor
protocol TerminalEngineSession: AnyObject {
    var view: NSView { get }
    var foregroundPID: pid_t? { get }
    var ttyName: String? { get }
    var isRunning: Bool { get }

    func focus()
    func blur()
    func setOccluded(_ occluded: Bool)
    func pollViewportSnapshot(readText: Bool) -> TerminalViewportSnapshot?
    func close()
}

extension TerminalEngineSession {
    var foregroundPID: pid_t? { nil }
    var ttyName: String? { nil }
    var isRunning: Bool { true }
    func pollViewportSnapshot(readText _: Bool) -> TerminalViewportSnapshot? { nil }
}
