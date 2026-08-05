import Foundation

actor GitInspector {
    private struct CachedResult {
        let metadata: GitMetadata?
        let insertedAt: Date
    }

    private var cache: [URL: CachedResult] = [:]
    private let cacheLifetime: TimeInterval
    private let debounceNanoseconds: UInt64

    init(cacheLifetime: TimeInterval = 2, debounceMilliseconds: UInt64 = 200) {
        self.cacheLifetime = cacheLifetime
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
    }

    func inspect(directory: URL) async -> GitMetadata? {
        guard !Task.isCancelled else { return nil }
        if debounceNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
        }
        guard !Task.isCancelled else { return nil }

        let directory = directory.standardizedFileURL
        if let cached = cache[directory], Date().timeIntervalSince(cached.insertedAt) < cacheLifetime {
            return cached.metadata
        }

        let metadata = inspectSynchronously(directory: directory)
        cache[directory] = CachedResult(metadata: metadata, insertedAt: Date())
        return metadata
    }

    func invalidate(directory: URL) {
        cache.removeValue(forKey: directory.standardizedFileURL)
    }

    private func inspectSynchronously(directory: URL) -> GitMetadata? {
        guard let rootString = runGit(
            arguments: ["-C", directory.path, "rev-parse", "--show-toplevel"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rootString.isEmpty
        else {
            return nil
        }

        let root = URL(fileURLWithPath: rootString).standardizedFileURL
        guard let status = runGit(
            arguments: ["-C", directory.path, "status", "--porcelain=v2", "--branch", "-z"],
            allowNonZeroExit: true
        ) else {
            return nil
        }

        let statusResult = GitStatusParser.parse(status)
        let unstaged = parseNumstat(
            runGit(arguments: ["-C", directory.path, "diff", "--numstat"], allowNonZeroExit: true)
        )
        let staged = parseNumstat(
            runGit(arguments: ["-C", directory.path, "diff", "--cached", "--numstat"], allowNonZeroExit: true)
        )

        return GitMetadata(
            root: root,
            branch: statusResult.branch,
            changedFiles: statusResult.paths.count,
            insertions: unstaged.insertions + staged.insertions,
            deletions: unstaged.deletions + staged.deletions,
            isDetachedHead: statusResult.isDetachedHead
        )
    }

    private func runGit(
        arguments: [String],
        allowNonZeroExit: Bool = false
    ) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = [
            "GIT_OPTIONAL_LOCKS": "0",
            "LC_ALL": "C",
            "LANG": "C"
        ]

        do {
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard allowNonZeroExit || process.terminationStatus == 0 else {
                return nil
            }
            return String(data: outputData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseNumstat(_ output: String?) -> (insertions: Int, deletions: Int) {
        guard let output else { return (0, 0) }
        var insertions = 0
        var deletions = 0

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            if let added = Int(fields[0]), let removed = Int(fields[1]) {
                insertions += added
                deletions += removed
            }
        }

        return (insertions, deletions)
    }
}

struct ParsedGitStatus {
    var branch: String = "HEAD"
    var paths: Set<String> = []
    var isDetachedHead = false
}

enum GitStatusParser {
    static func parse(_ output: String) -> ParsedGitStatus {
        var result = ParsedGitStatus()
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: false)

        var index = 0
        while index < tokens.count {
            let token = String(tokens[index])
            if token.hasPrefix("# branch.head ") {
                let branch = String(token.dropFirst("# branch.head ".count))
                if branch == "(detached)" || branch == "(unknown)" {
                    result.branch = "HEAD"
                    result.isDetachedHead = true
                } else if !branch.isEmpty {
                    result.branch = branch
                }
            } else if token.hasPrefix("? ") {
                result.paths.insert(String(token.dropFirst(2)))
            } else if token.hasPrefix("1 ") || token.hasPrefix("u ") {
                if let path = token.split(separator: " ").last {
                    result.paths.insert(String(path))
                }
            } else if token.hasPrefix("2 ") {
                let fields = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                if let path = fields.last {
                    result.paths.insert(String(path.split(separator: "\t").first ?? path))
                }
                if index + 1 < tokens.count, !tokens[index + 1].isEmpty {
                    result.paths.insert(String(tokens[index + 1]))
                    index += 1
                }
            }
            index += 1
        }

        return result
    }
}
