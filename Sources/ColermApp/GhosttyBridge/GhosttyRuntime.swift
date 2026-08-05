import Foundation

@MainActor
final class GhosttyRuntime {
    private(set) var status: GhosttyRuntimeStatus = .stopped
    private var sessions: [UUID: GhosttySession] = [:]
    private var started = false

    var onAction: ((GhosttyAction) -> Void)?

    func start() {
        guard !started else { return }
        started = true

        if let resourcesURL = GhosttyResources.resourceURL {
            setenv("GHOSTTY_RESOURCES_DIR", resourcesURL.path, 1)
        }
        status = .ready
    }

    func createSession(options: SessionLaunchOptions, id: UUID = UUID()) -> GhosttySession {
        let session = GhosttySession(id: id, options: options) { [weak self] action in
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
        status = .stopped
        started = false
    }
}

private enum GhosttyResources {
    static var resourceURL: URL? {
        let candidate = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let shellIntegration = candidate.appendingPathComponent(
            "shell-integration/zsh/ghostty-integration"
        )
        guard FileManager.default.fileExists(atPath: shellIntegration.path) else {
            return nil
        }
        return candidate
    }
}
