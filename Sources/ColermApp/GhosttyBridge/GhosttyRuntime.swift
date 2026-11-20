import Foundation
import GhosttyTerminal

@MainActor
final class GhosttyRuntime {
    private(set) var status: GhosttyRuntimeStatus = .stopped
    private var sessions: [UUID: GhosttySession] = [:]
    private var statusEventChannel: AgentStatusEventChannel?
    private var started = false

    var onAction: ((GhosttyAction) -> Void)?
    var statusDirectoryPath: String? { statusEventChannel?.directoryPath }

    deinit {
        statusEventChannel?.stop()
    }

    func start() {
        guard !started else { return }
        started = true

        if let resourcesURL = GhosttyResources.resourceURL {
            setenv("GHOSTTY_RESOURCES_DIR", resourcesURL.path, 1)
        }
        statusEventChannel = AgentStatusEventChannel { [weak self] sessionID, hint in
            self?.onAction?(.agentStatusHint(sessionID, hint))
        }
        status = .ready
    }

    func createSession(options: SessionLaunchOptions, id: UUID = UUID()) -> GhosttySession {
        let session = GhosttySession(
            id: id,
            options: options,
            statusDirectoryPath: statusEventChannel?.directoryPath,
            agentHookPath: GhosttyResources.agentHookScriptURL?.path,
            claudeHooksFilePath: GhosttyResources.claudeHooksConfigURL?.path
        ) { [weak self] action in
            self?.onAction?(action)
        }
        sessions[id] = session
        return session
    }

    func destroySession(_ session: GhosttySession) {
        session.close()
        sessions.removeValue(forKey: session.id)
    }

    func stop() {
        sessions.values.forEach { $0.close() }
        sessions.removeAll()
        statusEventChannel?.stop()
        statusEventChannel = nil
        status = .stopped
        started = false
    }
}

private enum GhosttyResources {
    static var resourceURL: URL? {
        if let bundled = GhosttyRuntimeResources.directoryURL,
           hasZshIntegration(in: bundled)
        {
            return bundled
        }
        let candidate = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        guard hasZshIntegration(in: candidate) else {
            return nil
        }
        return candidate
    }

    static var agentHookScriptURL: URL? {
        shellIntegrationFile(named: "colerm-agent-hook.sh")
    }

    static var claudeHooksConfigURL: URL? {
        shellIntegrationFile(named: "colerm-claude-hooks.json")
    }

    private static func shellIntegrationFile(named filename: String) -> URL? {
        let candidates: [URL?] = [
            resourceURL?.appendingPathComponent("shell-integration/zsh/\(filename)"),
            Bundle.main.resourceURL?.appendingPathComponent("shell-integration/zsh/\(filename)"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/shell-integration/zsh/\(filename)")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func hasZshIntegration(in directory: URL) -> Bool {
        let shellIntegration = directory.appendingPathComponent(
            "shell-integration/zsh/ghostty-integration"
        )
        return FileManager.default.fileExists(atPath: shellIntegration.path)
    }
}
