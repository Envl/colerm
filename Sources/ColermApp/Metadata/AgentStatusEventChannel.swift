import Darwin
import Foundation

final class AgentStatusEventChannel: @unchecked Sendable {
    typealias EventHandler = @MainActor @Sendable (TerminalSessionID, String) -> Void

    private static let maxFileBytes = 4096

    let directoryPath: String

    private let queue = DispatchQueue(label: "com.colerm.agent-status-channel", qos: .utility)
    private let onEvent: EventHandler
    private var dirFD: Int32 = -1
    private var watchSource: DispatchSourceFileSystemObject?
    private var isStopped = false

    init?(directoryPath: String? = nil, onEvent: @escaping EventHandler) {
        let resolvedPath = directoryPath ?? Self.makeDefaultDirectoryPath()
        do {
            try FileManager.default.createDirectory(
                atPath: resolvedPath,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }

        let fd = Darwin.open(resolvedPath, O_EVTONLY)
        guard fd >= 0 else {
            try? FileManager.default.removeItem(atPath: resolvedPath)
            return nil
        }
        _ = Darwin.fcntl(fd, F_SETFD, FD_CLOEXEC)

        self.directoryPath = resolvedPath
        self.onEvent = onEvent
        self.dirFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.drainPendingEvents()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        self.watchSource = source
        source.resume()

        // Drain any files that may have been written before the source resumed.
        queue.async { [weak self] in
            self?.drainPendingEvents()
        }
    }

    deinit {
        stop()
    }

    func stop() {
        let path = directoryPath
        queue.sync {
            guard !isStopped else { return }
            isStopped = true

            if let watchSource {
                self.watchSource = nil
                dirFD = -1
                watchSource.cancel()
            } else if dirFD >= 0 {
                Darwin.close(dirFD)
                dirFD = -1
            }
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func drainPendingEvents() {
        guard !isStopped else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else {
            return
        }

        struct QueuedFile {
            let path: String
            let name: String
            let mtimeSec: Int
            let mtimeNsec: Int
        }

        var files: [QueuedFile] = []
        files.reserveCapacity(entries.count)

        for name in entries where !name.hasPrefix(".") {
            let fullPath = (directoryPath as NSString).appendingPathComponent(name)
            var st = stat()
            guard Darwin.lstat(fullPath, &st) == 0,
                  (st.st_mode & S_IFMT) == S_IFREG
            else {
                continue
            }
            files.append(
                QueuedFile(
                    path: fullPath,
                    name: name,
                    mtimeSec: st.st_mtimespec.tv_sec,
                    mtimeNsec: st.st_mtimespec.tv_nsec
                )
            )
        }

        guard !files.isEmpty else { return }

        files.sort { lhs, rhs in
            if lhs.mtimeSec != rhs.mtimeSec { return lhs.mtimeSec < rhs.mtimeSec }
            if lhs.mtimeNsec != rhs.mtimeNsec { return lhs.mtimeNsec < rhs.mtimeNsec }
            return lhs.name < rhs.name
        }

        var collectedEvents: [(TerminalSessionID, String)] = []
        for file in files {
            let data = Self.readBoundedFile(atPath: file.path)
            _ = Darwin.unlink(file.path)
            guard let data, let payload = String(data: data, encoding: .utf8) else {
                continue
            }
            collectedEvents.append(contentsOf: Self.parsePayload(payload))
        }

        guard !collectedEvents.isEmpty else { return }
        let handler = onEvent
        Task { @MainActor in
            for (sessionID, hint) in collectedEvents {
                handler(sessionID, hint)
            }
        }
    }

    private static func readBoundedFile(atPath path: String) -> Data? {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var buffer = [UInt8](repeating: 0, count: maxFileBytes)
        var total = 0
        while total < maxFileBytes {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base.advanced(by: total), maxFileBytes - total)
            }
            if count > 0 {
                total += count
            } else {
                break
            }
        }
        guard total > 0 else { return nil }
        return Data(buffer[0 ..< total])
    }

    static func parsePayload(_ raw: String) -> [(TerminalSessionID, String)] {
        var results: [(TerminalSessionID, String)] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let parsed = parseLine(line) {
                results.append(parsed)
            }
        }
        return results
    }

    private static func parseLine(_ line: String) -> (TerminalSessionID, String)? {
        if line.hasPrefix("{"), let data = line.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let rawSessionID = (object["session_id"] ?? object["sessionId"]) as? String,
                  let sessionID = UUID(uuidString: rawSessionID.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return nil
            }
            if let rawHint = object["hint"] as? String {
                let trimmed = rawHint.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : (sessionID, trimmed)
            }
            guard let rawState = object["state"] as? String, !rawState.isEmpty else {
                return nil
            }
            var parts = ["state=\(rawState)"]
            if let kind = object["kind"] as? String, !kind.isEmpty {
                parts.append("kind=\(kind)")
            }
            if let app = (object["app"] ?? object["agent"]) as? String, !app.isEmpty {
                parts.append("app=\(app)")
            }
            if let auth = object["authoritative"] as? Bool, auth {
                parts.append("auth=1")
            } else if let authNum = object["auth"] as? Int, authNum != 0 {
                parts.append("auth=1")
            }
            return (sessionID, parts.joined(separator: ":"))
        }

        guard let separatorIndex = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }
        let rawID = String(line[..<separatorIndex])
        guard let sessionID = UUID(uuidString: rawID) else { return nil }
        let hint = line[line.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hint.isEmpty else { return nil }
        return (sessionID, hint)
    }

    private static func makeDefaultDirectoryPath() -> String {
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let dirName = "colerm-status-\(getpid())-\(suffix)"
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(dirName)
    }
}
