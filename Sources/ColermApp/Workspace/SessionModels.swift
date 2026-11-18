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
    static let defaultDiffSidebarWidth: CGFloat = 440
    static let minimumDiffSidebarWidth: CGFloat = 280
    static let maximumDiffSidebarWidth: CGFloat = 960
    static let diffSidebarDividerWidth: CGFloat = 1

    let id: TerminalSessionID
    let launchOptions: SessionLaunchOptions
    let engine: any TerminalEngineSession

    @Published private(set) var customTitle: String?
    @Published private(set) var metadata: SessionMetadata
    @Published private(set) var processState: SessionProcessState = .launching
    @Published private(set) var isActive = false
    @Published private(set) var isOccluded = true
    @Published private(set) var isForegroundCommandRunning = false
    @Published private(set) var agentStatus: AgentSessionStatus?
    @Published private(set) var columnWidth: CGFloat
    @Published private(set) var isDiffSidebarVisible = false
    @Published private(set) var diffSidebarWidth: CGFloat = TerminalSession.defaultDiffSidebarWidth
    @Published private(set) var diffSnapshot: GitDiffSnapshot?
    @Published private(set) var isLoadingDiff = false

    private var idleForegroundPID: pid_t?
    private var shellIntegrationActivityDetected = false
    private var agentTracker = AgentActivityTracker()

    var view: NSView { engine.view }
    var cwd: URL? { metadata.cwd }
    var effectiveColumnWidth: CGFloat {
        guard isDiffSidebarVisible else { return columnWidth }
        return columnWidth + Self.diffSidebarDividerWidth + diffSidebarWidth
    }
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
        if active {
            _ = clearCompletedAgentStatus()
        }
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
        diffSnapshot = nil
        objectWillChange.send()
    }

    func updateTitle(_ title: String?, now: TimeInterval = Date().timeIntervalSince1970) {
        let cleaned = title?.trimmingCharacters(in: .controlCharacters)
        if let cleaned {
            syncAgentStatus {
                $0.handleTitleChange(cleaned, isTabSelected: isActive, now: now)
            }
        }
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

    func setDiffSidebarVisible(_ visible: Bool) {
        guard isDiffSidebarVisible != visible else { return }
        isDiffSidebarVisible = visible
        if !visible {
            isLoadingDiff = false
        }
    }

    @discardableResult
    func toggleDiffSidebar() -> Bool {
        let next = !isDiffSidebarVisible
        setDiffSidebarVisible(next)
        return next
    }

    func updateDiffSidebarWidth(_ width: CGFloat) {
        guard width.isFinite else { return }
        let boundedWidth = min(
            max(width, Self.minimumDiffSidebarWidth),
            Self.maximumDiffSidebarWidth
        )
        guard diffSidebarWidth != boundedWidth else { return }
        diffSidebarWidth = boundedWidth
    }

    func setLoadingDiff(_ loading: Bool) {
        guard isLoadingDiff != loading else { return }
        isLoadingDiff = loading
    }

    func updateDiffSnapshot(_ snapshot: GitDiffSnapshot?) {
        guard diffSnapshot != snapshot else { return }
        diffSnapshot = snapshot
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

    func commandStarted(
        commandLine: String? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        shellIntegrationActivityDetected = true
        metadata.isAtPrompt = false
        isForegroundCommandRunning = true
        syncAgentStatus {
            $0.commandStarted(commandLine: commandLine, isTabSelected: isActive, now: now)
        }
        objectWillChange.send()
    }

    func commandFinished(
        exitCode: Int32?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        shellIntegrationActivityDetected = true
        metadata.lastExitCode = exitCode
        metadata.isAtPrompt = true
        isForegroundCommandRunning = false
        syncAgentStatus {
            $0.commandFinished(exitCode: exitCode, isTabSelected: isActive, now: now)
        }
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

    func handleUserInput(
        _ kind: TerminalUserInputKind,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        syncAgentStatus {
            $0.handleUserInput(kind, now: now)
        }
    }

    func handleProgressReport(
        _ state: GhosttyProgressState,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        syncAgentStatus {
            $0.handleProgressReport(state, isTabSelected: isActive, now: now)
        }
    }

    func handleAgentCompletionHint(now: TimeInterval = Date().timeIntervalSince1970) {
        syncAgentStatus {
            $0.handleCompletionNotificationHint(now: now)
        }
    }

    func handleAgentDesktopNotification(
        title: String,
        body: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        syncAgentStatus {
            $0.handleDesktopNotification(title: title, body: body, now: now)
        }
    }

    func handleExplicitAgentStatusHint(
        _ rawHint: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        syncAgentStatus {
            $0.handleExplicitHint(rawHint, isTabSelected: isActive, now: now)
        }
    }

    @discardableResult
    func clearCompletedAgentStatus() -> Bool {
        syncAgentStatus { $0.clearCompletedStatus() }
    }

    func close() {
        guard processState != .closed else { return }
        processState = .closed
        isForegroundCommandRunning = false
        agentStatus = nil
        engine.close()
    }

    @discardableResult
    func refreshForegroundActivity(
        agentInspector: (any AgentProcessInspecting)? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        if processState == .launching, engine.isRunning {
            processState = .running
            objectWillChange.send()
        }

        let foregroundChanged = updateForegroundCommandFallback()
        var agentChanged = false

        if let agentInspector {
            let observation: AgentProcessObservation?
            let canObserveProcesses: Bool

            if shellIntegrationActivityDetected && !isForegroundCommandRunning {
                observation = nil
                canObserveProcesses = true
            } else if processState.isRunning,
                      engine.isRunning,
                      let foregroundPID = engine.foregroundPID {
                observation = agentInspector.inspect(foregroundPID: foregroundPID)
                canObserveProcesses = true
            } else if shellIntegrationActivityDetected && isForegroundCommandRunning {
                observation = nil
                canObserveProcesses = false
            } else {
                observation = nil
                canObserveProcesses = true
            }

            let shouldReadViewport = observation != nil || agentStatus != nil
            let viewport = engine.pollViewportSnapshot(readText: shouldReadViewport)

            agentChanged = syncAgentStatus {
                $0.poll(
                    observation: observation,
                    viewport: viewport,
                    canObserveProcesses: canObserveProcesses,
                    isTabSelected: isActive,
                    now: now
                )
            }
        }

        return foregroundChanged || agentChanged
    }

    private func updateForegroundCommandFallback() -> Bool {
        let wasRunning = isForegroundCommandRunning
        guard !shellIntegrationActivityDetected else { return false }

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

    @discardableResult
    private func syncAgentStatus(_ mutate: (inout AgentActivityTracker) -> Bool) -> Bool {
        let previous = agentStatus
        _ = mutate(&agentTracker)
        if agentStatus != agentTracker.status {
            agentStatus = agentTracker.status
            return true
        }
        return previous != agentStatus
    }
}
