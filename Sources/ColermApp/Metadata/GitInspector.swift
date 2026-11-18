import Foundation

actor GitInspector {
    private struct CachedResult {
        let metadata: GitMetadata?
        let insertedAt: Date
    }

    private struct GitCommandOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
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

    func invalidateAll() {
        cache.removeAll()
    }

    func listBranches(directory: URL) -> GitBranchList? {
        let directory = directory.standardizedFileURL
        guard let rootString = runGit(
            arguments: ["-C", directory.path, "rev-parse", "--show-toplevel"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rootString.isEmpty
        else {
            return nil
        }

        let symbolicHead = runGit(
            arguments: ["-c", "core.quotePath=false", "-C", directory.path, "symbolic-ref", "--quiet", "--short", "HEAD"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let isDetachedHead = symbolicHead == nil || symbolicHead?.isEmpty == true
        let currentBranch = (symbolicHead?.isEmpty == false ? symbolicHead : nil) ?? "HEAD"

        let refsOutput = runGit(
            arguments: [
                "-c", "core.quotePath=false",
                "-C", directory.path,
                "for-each-ref",
                "--format=%(refname)%09%(refname:short)%09%(HEAD)%09%(symref)",
                "refs/heads",
                "refs/remotes"
            ]
        ) ?? ""

        return GitBranchParser.parse(
            refsOutput,
            currentBranch: currentBranch,
            isDetachedHead: isDetachedHead
        )
    }

    func switchBranch(
        _ branch: GitBranch,
        directory: URL
    ) -> Result<Void, GitBranchSwitchError> {
        if !branch.isRemote, branch.isCurrent {
            return .success(())
        }

        let directory = directory.standardizedFileURL
        let arguments: [String]
        if branch.isRemote {
            arguments = ["-C", directory.path, "switch", "--track", branch.name]
        } else {
            arguments = ["-C", directory.path, "switch", branch.name]
        }

        guard let output = runGitCommand(arguments: arguments, readOnly: false) else {
            return .failure(
                GitBranchSwitchError(
                    branchName: branch.localName,
                    message: "Failed to launch git switch."
                )
            )
        }

        cache.removeAll()

        guard output.exitCode == 0 else {
            let trimmedError = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOut = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = !trimmedError.isEmpty
                ? trimmedError
                : (!trimmedOut.isEmpty ? trimmedOut : "git switch exited with code \(output.exitCode).")
            return .failure(
                GitBranchSwitchError(
                    branchName: branch.localName,
                    message: message
                )
            )
        }

        return .success(())
    }

    func inspectDiff(directory: URL) -> GitDiffSnapshot? {
        guard !Task.isCancelled else { return nil }
        let directory = directory.standardizedFileURL
        guard let rootString = runGit(
            arguments: ["-C", directory.path, "rev-parse", "--show-toplevel"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rootString.isEmpty
        else {
            return nil
        }

        let root = URL(fileURLWithPath: rootString).standardizedFileURL
        guard let status = runGit(
            arguments: [
                "-c", "core.quotePath=false",
                "-C", root.path,
                "status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"
            ],
            allowNonZeroExit: true
        ) else {
            return nil
        }

        let statusResult = GitStatusParser.parse(status)
        let diffBase = resolveDiffBase(root: root)

        var rawPatch = ""
        var files: [GitFileDiff] = []
        if let diffBase,
           let rawDiff = runGit(
               arguments: [
                   "-c", "core.quotePath=false",
                   "-C", root.path,
                   "diff", diffBase,
                   "--unified=3",
                   "--no-color",
                   "--no-ext-diff",
                   "--find-renames"
               ],
               allowNonZeroExit: true
           ) {
            rawPatch = rawDiff
            files.append(contentsOf: GitDiffParser.parseUnifiedDiff(rawDiff))
        }

        var untrackedFiles: [GitUntrackedDiffFile] = []
        let trackedPaths = Set(files.map(\.path))
        for untrackedPath in statusResult.untrackedPaths.prefix(100) where !trackedPaths.contains(untrackedPath) {
            guard !Task.isCancelled else { return nil }
            let fileURL = root.appendingPathComponent(untrackedPath)
            if let result = GitDiffParser.readUntrackedDiffFile(
                relativePath: untrackedPath,
                fileURL: fileURL
            ) {
                untrackedFiles.append(result.untracked)
                files.append(result.summary)
            }
        }

        files.sort {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        let totalInsertions = files.reduce(0) { $0 + $1.insertions }
        let totalDeletions = files.reduce(0) { $0 + $1.deletions }

        return GitDiffSnapshot(
            root: root,
            branch: statusResult.branch,
            rawPatch: rawPatch,
            untrackedFiles: untrackedFiles,
            files: files,
            totalInsertions: totalInsertions,
            totalDeletions: totalDeletions
        )
    }

    func loadFileDetail(
        directory: URL,
        relativePath: String,
        kind: String
    ) -> GitLoadedFileDetail? {
        guard !relativePath.isEmpty else { return nil }
        let directory = directory.standardizedFileURL
        guard let rootString = runGit(
            arguments: ["-C", directory.path, "rev-parse", "--show-toplevel"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rootString.isEmpty
        else {
            return nil
        }

        let root = URL(fileURLWithPath: rootString).standardizedFileURL
        let fileURL = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard fileURL.path.hasPrefix(rootPrefix) else {
            return nil
        }

        if let detail = GitDiffParser.loadFileDetailFromDisk(
            relativePath: relativePath,
            kind: kind,
            fileURL: fileURL
        ) {
            return detail
        }

        if kind == "D",
           let headContent = runGit(
               arguments: ["-c", "core.quotePath=false", "-C", root.path, "show", "HEAD:\(relativePath)"]
           ) {
            return GitLoadedFileDetail(
                path: relativePath,
                kind: kind,
                textContents: String(headContent.prefix(GitDiffParser.defaultMaximumDetailBytes)),
                imageDataURL: nil,
                truncatedNote: headContent.utf8.count > GitDiffParser.defaultMaximumDetailBytes
                    ? "Truncated preview"
                    : nil,
                errorNote: nil
            )
        }

        return nil
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
            arguments: [
                "-c", "core.quotePath=false",
                "-C", root.path,
                "status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"
            ],
            allowNonZeroExit: true
        ) else {
            return nil
        }

        let statusResult = GitStatusParser.parse(status)
        let diffBase = resolveDiffBase(root: root)
        let trackedStats: (paths: Set<String>, insertions: Int, deletions: Int)
        if let diffBase {
            trackedStats = parseNumstatZ(
                runGit(
                    arguments: [
                        "-c", "core.quotePath=false",
                        "-C", root.path,
                        "diff", diffBase,
                        "--numstat",
                        "--find-renames",
                        "-z"
                    ],
                    allowNonZeroExit: true
                )
            )
        } else {
            trackedStats = ([], 0, 0)
        }

        var untrackedCount = 0
        var untrackedInsertions = 0
        for untrackedPath in statusResult.untrackedPaths.prefix(100) where !trackedStats.paths.contains(untrackedPath) {
            let fileURL = root.appendingPathComponent(untrackedPath)
            if let lines = GitDiffParser.untrackedFileInsertionCount(
                relativePath: untrackedPath,
                fileURL: fileURL
            ) {
                untrackedCount += 1
                untrackedInsertions += lines
            }
        }

        return GitMetadata(
            root: root,
            branch: statusResult.branch,
            changedFiles: trackedStats.paths.count + untrackedCount,
            insertions: trackedStats.insertions + untrackedInsertions,
            deletions: trackedStats.deletions,
            isDetachedHead: statusResult.isDetachedHead
        )
    }

    private func resolveDiffBase(root: URL) -> String? {
        let hasHead = runGit(
            arguments: ["-C", root.path, "rev-parse", "--verify", "HEAD"]
        ) != nil
        if hasHead {
            return "HEAD"
        }
        let emptyTree = runGit(
            arguments: ["-C", root.path, "hash-object", "-t", "tree", "/dev/null"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        return emptyTree?.isEmpty == false ? emptyTree : nil
    }

    private func runGit(
        arguments: [String],
        allowNonZeroExit: Bool = false
    ) -> String? {
        guard let output = runGitCommand(arguments: arguments, readOnly: true) else {
            return nil
        }
        guard allowNonZeroExit || output.exitCode == 0 else {
            return nil
        }
        return output.stdout
    }

    private func runGitCommand(
        arguments: [String],
        readOnly: Bool
    ) -> GitCommandOutput? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = readOnly ? FileHandle.nullDevice : stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        if readOnly {
            environment["GIT_OPTIONAL_LOCKS"] = "0"
        }
        process.environment = environment

        do {
            try process.run()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = readOnly ? Data() : stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return GitCommandOutput(
                exitCode: process.terminationStatus,
                stdout: String(decoding: stdoutData, as: UTF8.self),
                stderr: String(decoding: stderrData, as: UTF8.self)
            )
        } catch {
            return nil
        }
    }

    private func parseNumstatZ(_ output: String?) -> (paths: Set<String>, insertions: Int, deletions: Int) {
        guard let output else { return ([], 0, 0) }
        var paths: Set<String> = []
        var insertions = 0
        var deletions = 0

        let tokens = output.split(separator: "\0", omittingEmptySubsequences: false)
        var index = 0
        while index < tokens.count {
            let token = String(tokens[index])
            if token.isEmpty {
                index += 1
                continue
            }

            let fields = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else {
                index += 1
                continue
            }

            if let added = Int(fields[0]), let removed = Int(fields[1]) {
                insertions += added
                deletions += removed
            }

            let pathField = String(fields[2])
            if pathField.isEmpty {
                // Rename or copy in `-z` format: `added\tdeleted\t\0old\0new\0`.
                if index + 2 < tokens.count {
                    let newPath = String(tokens[index + 2])
                    if !newPath.isEmpty {
                        paths.insert(newPath)
                    }
                    index += 2
                }
            } else {
                paths.insert(pathField)
            }
            index += 1
        }

        return (paths, insertions, deletions)
    }
}

struct ParsedGitStatus {
    var branch: String = "HEAD"
    var paths: Set<String> = []
    var untrackedPaths: [String] = []
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
                let path = String(token.dropFirst(2))
                result.paths.insert(path)
                result.untrackedPaths.append(path)
            } else if token.hasPrefix("1 ") {
                let fields = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                if fields.count >= 9 {
                    result.paths.insert(String(fields[8]))
                } else if let path = fields.last {
                    result.paths.insert(String(path))
                }
            } else if token.hasPrefix("u ") {
                let fields = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
                if fields.count >= 11 {
                    result.paths.insert(String(fields[10]))
                } else if let path = fields.last {
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
