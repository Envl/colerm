import Combine
import Foundation
import AppKit

typealias TerminalSessionID = UUID

enum WorkspaceTabTitle {
    static func folderName(cwd: URL?, gitRoot: URL?) -> String {
        if let name = nonEmptyLastPathComponent(of: cwd) {
            return name
        }
        if let name = nonEmptyLastPathComponent(of: gitRoot) {
            return name
        }
        return "New Column"
    }

    private static func nonEmptyLastPathComponent(of url: URL?) -> String? {
        guard let url else { return nil }
        let standardizedPath = url.standardizedFileURL.path
        if standardizedPath == "/" {
            return "/"
        }
        let name = url.lastPathComponent
        return name.isEmpty ? nil : name
    }
}

struct GitMetadata: Equatable, Codable {
    var root: URL
    var branch: String
    var changedFiles: Int
    var insertions: Int
    var deletions: Int
    var isDetachedHead: Bool
}

struct RuntimeMetadata: Equatable, Codable {
    var name: String
    var path: URL?
    var version: String?
}

struct SessionMetadata: Equatable {
    var cwd: URL?
    var title: String?
    var runtime: RuntimeMetadata?
    var git: GitMetadata?
    var lastExitCode: Int32?
    var isAtPrompt: Bool

    static let empty = SessionMetadata(
        cwd: nil,
        title: nil,
        runtime: nil,
        git: nil,
        lastExitCode: nil,
        isAtPrompt: false
    )
}

enum SessionProcessState: Equatable {
    case launching
    case running
    case exited(Int32)
    case closed

    var isRunning: Bool {
        switch self {
        case .launching, .running:
            return true
        case .exited, .closed:
            return false
        }
    }
}

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: TerminalSessionID
    let launchOptions: SessionLaunchOptions
    let engine: any TerminalEngineSession

    @Published private(set) var customTitle: String?
    @Published private(set) var metadata: SessionMetadata
    @Published private(set) var processState: SessionProcessState = .launching
    @Published private(set) var isActive = false
    @Published private(set) var isOccluded = true
    @Published private(set) var isForegroundCommandRunning = false
    @Published private(set) var columnWidth: CGFloat

    private var idleForegroundPID: pid_t?

    var view: NSView { engine.view }
    var cwd: URL? { metadata.cwd }
    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }
        if let title = metadata.title, !title.isEmpty {
            return title
        }
        return cwd?.lastPathComponent ?? "New Column"
    }

    init(
        id: TerminalSessionID = UUID(),
        launchOptions: SessionLaunchOptions,
        engine: any TerminalEngineSession,
        customTitle: String? = nil,
        columnWidth: CGFloat = 600
    ) {
        self.id = id
        self.launchOptions = launchOptions
        self.engine = engine
        self.customTitle = customTitle
        self.columnWidth = columnWidth
        self.metadata = SessionMetadata(cwd: launchOptions.workingDirectory, title: nil, runtime: nil, git: nil, lastExitCode: nil, isAtPrompt: false)
        self.processState = engine.isRunning ? .running : .launching
    }

    func setActive(_ active: Bool) {
        guard isActive != active else {
            if active { engine.focus() }
            return
        }
        isActive = active
        if active {
            engine.focus()
        } else {
            engine.blur()
        }
    }

    func setOccluded(_ occluded: Bool) {
        guard isOccluded != occluded else { return }
        isOccluded = occluded
        engine.setOccluded(occluded)
    }

    func updateDirectory(_ directory: URL?) {
        guard metadata.cwd != directory else { return }
        metadata.cwd = directory
        metadata.git = nil
        objectWillChange.send()
    }

    func updateTitle(_ title: String?) {
        let cleaned = title?.trimmingCharacters(in: .controlCharacters)
        guard metadata.title != cleaned else { return }
        metadata.title = cleaned
        objectWillChange.send()
    }

    func updateCustomTitle(_ title: String?) {
        let cleaned = title?.trimmingCharacters(in: .controlCharacters)
        guard customTitle != cleaned else { return }
        customTitle = cleaned
        objectWillChange.send()
    }

    func updateColumnWidth(_ width: CGFloat) {
        let boundedWidth = max(width, 320)
        guard columnWidth != boundedWidth else { return }
        columnWidth = boundedWidth
    }

    func updateRuntime(_ runtime: RuntimeMetadata?) {
        guard metadata.runtime != runtime else { return }
        metadata.runtime = runtime
        objectWillChange.send()
    }

    func updateGit(_ git: GitMetadata?) {
        guard metadata.git != git else { return }
        metadata.git = git
        objectWillChange.send()
    }

    func commandFinished(exitCode: Int32?) {
        metadata.lastExitCode = exitCode
        metadata.isAtPrompt = true
        if let foregroundPID = engine.foregroundPID {
            idleForegroundPID = foregroundPID
        }
        isForegroundCommandRunning = false
        if let exitCode {
            processState = .running
            objectWillChange.send()
            if exitCode != 0 {
                metadata.lastExitCode = exitCode
            }
        } else {
            objectWillChange.send()
        }
    }

    func close() {
        guard processState != .closed else { return }
        processState = .closed
        isForegroundCommandRunning = false
        engine.close()
    }

    @discardableResult
    func refreshForegroundActivity() -> Bool {
        let wasRunning = isForegroundCommandRunning

        if processState == .launching, engine.isRunning {
            processState = .running
            objectWillChange.send()
        }

        guard processState.isRunning,
              engine.isRunning,
              let foregroundPID = engine.foregroundPID else {
            isForegroundCommandRunning = false
            idleForegroundPID = nil
            return wasRunning != isForegroundCommandRunning
        }

        if let idleForegroundPID {
            isForegroundCommandRunning = foregroundPID != idleForegroundPID
        } else {
            self.idleForegroundPID = foregroundPID
            isForegroundCommandRunning = false
        }

        return wasRunning != isForegroundCommandRunning
    }
}
