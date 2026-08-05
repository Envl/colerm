import Foundation

struct PersistedSession: Codable, Equatable {
    var id: UUID
    var cwd: URL?
    var customTitle: String?
    var columnWidth: CGFloat
}

struct PersistedWorkspace: Codable, Equatable {
    var selectedSessionID: UUID?
    var sessions: [PersistedSession]
}

final class WorkspacePersistence {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() -> PersistedWorkspace? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }

    func save(_ workspace: PersistedWorkspace) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(workspace)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent(
                Self.supportDirectoryName(bundleIdentifier: Bundle.main.bundleIdentifier),
                isDirectory: true
            )
            .appendingPathComponent("workspace.json")
    }

    static func supportDirectoryName(bundleIdentifier: String?) -> String {
        bundleIdentifier == "com.colerm.app.debug" ? "Colerm Debug" : "Colerm"
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
