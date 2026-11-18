import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

enum GhosttyAction {
    case newColumn(origin: TerminalSessionID)
    case closeColumn(origin: TerminalSessionID)
    case surfaceClosed(TerminalSessionID, processAlive: Bool)
    case gotoRelative(Int)
    case gotoColumn(Int)
    case workingDirectory(TerminalSessionID, URL)
    case title(TerminalSessionID, String)
    case commandStarted(TerminalSessionID, commandLine: String?)
    case commandFinished(TerminalSessionID, Int32?)
    case progressReport(TerminalSessionID, GhosttyProgressState)
    case userInput(TerminalSessionID, TerminalUserInputKind)
    case agentStatusHint(TerminalSessionID, String)
    case columnMetadata(TerminalSessionID, String)
    case desktopNotification(TerminalSessionID, title: String, body: String)
    case ringBell(TerminalSessionID)
    case openURL(URL)
    case secureInput(Bool)
    case closeWindow
}

@MainActor
final class WorkspaceStore: ObservableObject {
    let runtime: GhosttyRuntime
    let persistence: WorkspacePersistence
    let gitInspector: GitInspector
    let agentInspector: any AgentProcessInspecting

    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var selectedSessionID: TerminalSessionID?
    @Published private(set) var selectionActivationID = UUID()
    @Published private(set) var runtimeStatus: GhosttyRuntimeStatus = .stopped
    @Published private(set) var bellSessionIDs: Set<TerminalSessionID> = []
    @Published private(set) var secureInputEnabled = false

    private var gitInspectionTasks: [TerminalSessionID: Task<Void, Never>] = [:]
    private var diffInspectionTasks: [TerminalSessionID: Task<Void, Never>] = [:]
    private var activityTimer: Timer?
    private var activityTickCount = 0

    convenience init() {
        self.init(
            persistence: WorkspacePersistence(),
            runtime: GhosttyRuntime(),
            gitInspector: GitInspector()
        )
    }

    init(
        persistence: WorkspacePersistence,
        runtime: GhosttyRuntime,
        gitInspector: GitInspector,
        agentInspector: (any AgentProcessInspecting)? = nil
    ) {
        self.persistence = persistence
        self.runtime = runtime
        self.gitInspector = gitInspector
        self.agentInspector = agentInspector ?? SystemAgentProcessInspector()
        runtime.onAction = { [weak self] action in
            self?.handle(action)
        }
        runtime.start()
        runtimeStatus = runtime.status
        restore()
        startActivityMonitoring()
    }

    deinit {
        gitInspectionTasks.values.forEach { $0.cancel() }
        diffInspectionTasks.values.forEach { $0.cancel() }
        activityTimer?.invalidate()
    }

    var selectedSession: TerminalSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var hasRunningSessions: Bool {
        sessions.contains { $0.processState.isRunning && $0.engine.isRunning }
    }

    func addColumn() {
        let insertionIndex = selectedSessionID
            .flatMap { sessionID in
                sessions.firstIndex { $0.id == sessionID }
            }
            .map { $0 + 1 }
        addColumn(
            workingDirectory: selectedSession?.cwd ?? currentDirectoryURL,
            insertionIndex: insertionIndex
        )
    }

    func addColumn(toLeftOf sessionID: TerminalSessionID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        _ = addColumn(workingDirectory: sessions[index].cwd, insertionIndex: index)
    }

    func addColumn(toRightOf sessionID: TerminalSessionID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        _ = addColumn(workingDirectory: sessions[index].cwd, insertionIndex: index + 1)
    }

    @discardableResult
    func addColumn(
        workingDirectory: URL?,
        customTitle: String? = nil,
        insertionIndex: Int? = nil,
        persist: Bool = true
    ) -> TerminalSession {
        let sessionID = UUID()
        let options = SessionLaunchOptions(workingDirectory: workingDirectory)
        let engine = runtime.createSession(options: options, id: sessionID)
        let session = TerminalSession(
            id: sessionID,
            launchOptions: options,
            engine: engine,
            customTitle: customTitle
        )
        if let insertionIndex {
            sessions = WorkspaceSessionOrdering.inserting(
                session,
                into: sessions,
                at: insertionIndex
            )
        } else {
            sessions.append(session)
        }
        select(sessionID, persist: false)
        if persist { save() }
        return session
    }

    @discardableResult
    func closeSelectedColumn(confirm: Bool = true) -> Bool {
        guard let selectedSession else { return false }
        return closeColumn(selectedSession.id, confirm: confirm)
    }

    @discardableResult
    func closeColumn(_ sessionID: TerminalSessionID, confirm: Bool = true) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        let session = sessions[index]

        if confirm, session.processState.isRunning, !confirmClose(session: session) {
            return false
        }

        gitInspectionTasks[sessionID]?.cancel()
        gitInspectionTasks.removeValue(forKey: sessionID)
        diffInspectionTasks[sessionID]?.cancel()
        diffInspectionTasks.removeValue(forKey: sessionID)
        session.close()
        if let ghosttySession = session.engine as? GhosttySession {
            runtime.destroySession(ghosttySession)
        }
        sessions.remove(at: index)

        if sessions.isEmpty {
            selectedSessionID = nil
        } else if selectedSessionID == sessionID {
            let replacementIndex = min(index, sessions.count - 1)
            select(sessions[replacementIndex].id, persist: false)
        }
        save()
        return true
    }

    func select(_ sessionID: TerminalSessionID, persist: Bool = true) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        selectionActivationID = UUID()
        bellSessionIDs.remove(sessionID)
        if selectedSessionID == sessionID {
            let hadCompletedAgent = selectedSession?.agentStatus?.phase == .done
            selectedSession?.setActive(true)
            if hadCompletedAgent {
                objectWillChange.send()
            }
            if let selectedSession {
                refreshMetadata(for: selectedSession, force: true)
            }
            return
        }

        selectedSession?.setActive(false)
        selectedSessionID = sessionID
        selectedSession?.setActive(true)
        if let selectedSession {
            refreshMetadata(for: selectedSession, force: true)
        }
        if persist { save() }
    }

    func moveSelection(by offset: Int) {
        guard !sessions.isEmpty,
              let selectedSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == selectedSessionID })
        else { return }

        let newIndex = min(max(currentIndex + offset, 0), sessions.count - 1)
        select(sessions[newIndex].id)
    }

    func selectColumn(number: Int) {
        guard number > 0, number <= sessions.count else { return }
        select(sessions[number - 1].id)
    }

    @discardableResult
    func moveColumn(
        _ sessionID: TerminalSessionID,
        toInsertionIndex insertionIndex: Int
    ) -> Bool {
        guard let sourceIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }

        let reordered = WorkspaceSessionOrdering.move(
            sessions,
            from: sourceIndex,
            toInsertionIndex: insertionIndex
        )
        guard reordered.map(\.id) != sessions.map(\.id) else { return false }

        sessions = reordered
        save()
        return true
    }

    func updateCustomTitle(_ title: String?, for sessionID: TerminalSessionID? = nil) {
        guard let session = session(for: sessionID ?? selectedSessionID) else { return }
        session.updateCustomTitle(title)
        save()
    }

    func refreshMetadata(for session: TerminalSession, force: Bool = false) {
        gitInspectionTasks[session.id]?.cancel()
        guard let directory = session.cwd else {
            session.updateGit(nil)
            if session.isDiffSidebarVisible {
                session.setDiffSidebarVisible(false)
                session.updateDiffSnapshot(nil)
                objectWillChange.send()
            }
            return
        }

        let inspector = gitInspector
        gitInspectionTasks[session.id] = Task { [weak self, weak session] in
            if force {
                await inspector.invalidate(directory: directory)
            }
            let result = await inspector.inspect(directory: directory)
            guard !Task.isCancelled else { return }
            guard let self, let session, session.cwd == directory else { return }
            session.updateGit(result)
            if result == nil, session.isDiffSidebarVisible {
                session.setDiffSidebarVisible(false)
                session.updateDiffSnapshot(nil)
            } else if session.isDiffSidebarVisible {
                self.refreshDiff(for: session)
            }
            self.objectWillChange.send()
        }
    }

    func listBranches(for sessionID: TerminalSessionID) async -> GitBranchList? {
        guard let directory = session(for: sessionID)?.cwd else { return nil }
        return await gitInspector.listBranches(directory: directory)
    }

    func switchBranch(
        to branch: GitBranch,
        for sessionID: TerminalSessionID
    ) async -> Result<Void, GitBranchSwitchError> {
        guard let targetSession = session(for: sessionID),
              let directory = targetSession.cwd
        else {
            return .failure(
                GitBranchSwitchError(
                    branchName: branch.localName,
                    message: "Terminal has no active working directory."
                )
            )
        }

        let gitRoot = targetSession.metadata.git?.root
        let result = await gitInspector.switchBranch(branch, directory: directory)
        if case .success = result {
            for candidate in sessions {
                if candidate.id == sessionID
                    || (gitRoot != nil && candidate.metadata.git?.root == gitRoot)
                    || candidate.cwd?.standardizedFileURL == directory.standardizedFileURL {
                    refreshMetadata(for: candidate, force: true)
                }
            }
        }
        return result
    }

    @discardableResult
    func toggleDiffSidebar(for sessionID: TerminalSessionID) -> Bool {
        guard let session = session(for: sessionID) else { return false }
        let isVisible = session.toggleDiffSidebar()
        if isVisible {
            refreshDiff(for: session)
        } else {
            diffInspectionTasks[session.id]?.cancel()
            diffInspectionTasks.removeValue(forKey: session.id)
        }
        objectWillChange.send()
        return isVisible
    }

    func setDiffSidebarVisible(_ visible: Bool, for sessionID: TerminalSessionID) {
        guard let session = session(for: sessionID),
              session.isDiffSidebarVisible != visible
        else { return }
        session.setDiffSidebarVisible(visible)
        if visible {
            refreshDiff(for: session)
        } else {
            diffInspectionTasks[session.id]?.cancel()
            diffInspectionTasks.removeValue(forKey: session.id)
        }
        objectWillChange.send()
    }

    func refreshDiff(for sessionID: TerminalSessionID) {
        guard let session = session(for: sessionID) else { return }
        refreshDiff(for: session)
    }

    func refreshDiff(for session: TerminalSession) {
        diffInspectionTasks[session.id]?.cancel()
        guard session.isDiffSidebarVisible, let directory = session.cwd else {
            session.setLoadingDiff(false)
            return
        }

        if session.diffSnapshot == nil {
            session.setLoadingDiff(true)
        }

        let inspector = gitInspector
        diffInspectionTasks[session.id] = Task { [weak self, weak session] in
            let snapshot = await inspector.inspectDiff(directory: directory)
            guard !Task.isCancelled else { return }
            guard let self, let session, session.cwd == directory else { return }
            session.updateDiffSnapshot(snapshot)
            if let snapshot, var git = session.metadata.git {
                git.root = snapshot.root
                git.branch = snapshot.branch
                git.changedFiles = snapshot.files.count
                git.insertions = snapshot.totalInsertions
                git.deletions = snapshot.totalDeletions
                session.updateGit(git)
            }
            session.setLoadingDiff(false)
            self.objectWillChange.send()
        }
    }

    func loadDiffFileDetail(
        relativePath: String,
        kind: String,
        for sessionID: TerminalSessionID
    ) async -> GitLoadedFileDetail? {
        guard let directory = session(for: sessionID)?.cwd else { return nil }
        return await gitInspector.loadFileDetail(
            directory: directory,
            relativePath: relativePath,
            kind: kind
        )
    }

    func receiveRuntimeMetadata(_ metadata: RuntimeMetadata?, for sessionID: TerminalSessionID) {
        guard let session = session(for: sessionID) else { return }
        session.updateRuntime(metadata)
        objectWillChange.send()
    }

    func handle(_ action: GhosttyAction) {
        switch action {
        case .newColumn:
            addColumn()
        case .closeColumn(let origin):
            _ = closeColumn(origin)
        case .surfaceClosed(let sessionID, let processAlive):
            _ = closeColumn(sessionID, confirm: processAlive)
        case .gotoRelative(let offset):
            moveSelection(by: offset)
        case .gotoColumn(let index):
            if index >= 0, index < sessions.count {
                select(sessions[index].id)
            }
        case .workingDirectory(let sessionID, let directory):
            guard let session = session(for: sessionID) else { return }
            session.updateDirectory(directory)
            refreshMetadata(for: session)
            save()
        case .title(let sessionID, let title):
            guard let session = session(for: sessionID) else { return }
            let previousAgentStatus = session.agentStatus
            session.updateTitle(title)
            if session.agentStatus != previousAgentStatus {
                objectWillChange.send()
            }
        case .commandStarted(let sessionID, let commandLine):
            guard let session = session(for: sessionID) else { return }
            session.commandStarted(commandLine: commandLine)
            objectWillChange.send()
        case .commandFinished(let sessionID, let exitCode):
            guard let session = session(for: sessionID) else { return }
            session.commandFinished(exitCode: exitCode)
            objectWillChange.send()
            refreshMetadata(for: session)
        case .progressReport(let sessionID, let state):
            guard let session = session(for: sessionID) else { return }
            let previousAgentStatus = session.agentStatus
            session.handleProgressReport(state)
            if session.agentStatus != previousAgentStatus {
                objectWillChange.send()
            }
        case .userInput(let sessionID, let inputKind):
            guard let session = session(for: sessionID) else { return }
            let previousAgentStatus = session.agentStatus
            session.handleUserInput(inputKind)
            if session.agentStatus != previousAgentStatus {
                objectWillChange.send()
            }
        case .agentStatusHint(let sessionID, let rawHint):
            guard let session = session(for: sessionID) else { return }
            let previousAgentStatus = session.agentStatus
            session.handleExplicitAgentStatusHint(rawHint)
            if session.agentStatus != previousAgentStatus {
                objectWillChange.send()
            }
        case .columnMetadata(let sessionID, let encodedPayload):
            guard let update = RuntimeMetadataParser.decodeBase64(encodedPayload) else { return }
            receiveRuntimeMetadata(update.runtime, for: sessionID)
        case .desktopNotification(let sessionID, let title, let body):
            if let session = session(for: sessionID) {
                let previousAgentStatus = session.agentStatus
                session.handleAgentDesktopNotification(title: title, body: body)
                if session.agentStatus != previousAgentStatus {
                    objectWillChange.send()
                }
            }
            deliverNotification(title: title, body: body)
        case .ringBell(let sessionID):
            bellSessionIDs.insert(sessionID)
            session(for: sessionID)?.handleAgentCompletionHint()
        case .openURL(let url):
            guard url.scheme == "https" || url.scheme == "http" else { return }
            NSWorkspace.shared.open(url)
        case .secureInput(let enabled):
            secureInputEnabled = enabled
        case .closeWindow:
            NSApp.keyWindow?.performClose(nil)
        }
    }

    func requestWindowClose() -> Bool {
        guard hasRunningSessions else { return true }
        let alert = NSAlert()
        alert.messageText = "Close Column?"
        alert.informativeText = "Running terminal sessions will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        sessions.forEach { $0.close() }
        runtime.stop()
        return true
    }

    func save() {
        let document = PersistedWorkspace(
            selectedSessionID: selectedSessionID,
            sessions: sessions.map {
                PersistedSession(
                    id: $0.id,
                    cwd: $0.cwd,
                    customTitle: $0.customTitle,
                    columnWidth: $0.columnWidth
                )
            }
        )
        try? persistence.save(document)
    }

    private func restore() {
        guard let persisted = persistence.load(), !persisted.sessions.isEmpty else {
            _ = addColumn(workingDirectory: currentDirectoryURL, persist: true)
            return
        }

        sessions = persisted.sessions.map { item in
            let options = SessionLaunchOptions(workingDirectory: item.cwd)
            let engine = runtime.createSession(options: options, id: item.id)
            return TerminalSession(
                id: item.id,
                launchOptions: options,
                engine: engine,
                customTitle: item.customTitle,
                columnWidth: item.columnWidth
            )
        }

        if let first = sessions.first {
            select(first.id, persist: false)
        }
        sessions.dropFirst().forEach { refreshMetadata(for: $0) }
    }

    private func startActivityMonitoring() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                activityTickCount += 1
                var countChanged = false
                for session in sessions {
                    let wasAgentRunning = session.agentStatus?.phase == .running
                    if session.refreshForegroundActivity(agentInspector: agentInspector) {
                        countChanged = true
                    }
                    if wasAgentRunning && session.agentStatus?.phase != .running {
                        refreshMetadata(for: session, force: true)
                    }
                }
                if countChanged {
                    objectWillChange.send()
                }
                if activityTickCount % 6 == 0 {
                    for session in sessions where session.isDiffSidebarVisible && !session.isOccluded {
                        refreshMetadata(for: session, force: true)
                    }
                }
            }
        }
        activityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func session(for id: TerminalSessionID?) -> TerminalSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    private func confirmClose(session: TerminalSession) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close \(session.displayTitle)?"
        alert.informativeText = "The running terminal process will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func deliverNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: "column-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}

private var currentDirectoryURL: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

enum WorkspaceSessionOrdering {
    static func inserting<Element>(
        _ element: Element,
        into elements: [Element],
        at insertionIndex: Int
    ) -> [Element] {
        var result = elements
        result.insert(element, at: min(max(insertionIndex, 0), result.count))
        return result
    }

    static func move<Element>(
        _ elements: [Element],
        from sourceIndex: Int,
        toInsertionIndex insertionIndex: Int
    ) -> [Element] {
        guard elements.indices.contains(sourceIndex) else { return elements }

        let boundedInsertionIndex = min(max(insertionIndex, 0), elements.count)
        let destinationIndex = boundedInsertionIndex > sourceIndex
            ? boundedInsertionIndex - 1
            : boundedInsertionIndex
        guard destinationIndex != sourceIndex else { return elements }

        var reordered = elements
        let element = reordered.remove(at: sourceIndex)
        reordered.insert(element, at: min(destinationIndex, reordered.count))
        return reordered
    }
}
