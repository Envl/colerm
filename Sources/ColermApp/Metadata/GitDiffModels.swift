import Foundation

struct GitBranch: Equatable, Hashable, Identifiable {
    var name: String
    var localName: String
    var isRemote: Bool
    var isCurrent: Bool

    var id: String {
        "\(isRemote ? "remote" : "local"):\(name)"
    }
}

struct GitBranchList: Equatable {
    var currentBranch: String
    var isDetachedHead: Bool
    var localBranches: [GitBranch]
    var remoteBranches: [GitBranch]
}

struct GitBranchSwitchError: LocalizedError, Equatable {
    let branchName: String
    let message: String

    var errorDescription: String? {
        message
    }
}

enum GitFileChangeKind: String, Equatable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "U"
    case unmerged = "!"
}

struct GitDiffLine: Equatable, Identifiable {
    enum Kind: Equatable {
        case context
        case addition
        case deletion
        case meta
    }

    let id: Int
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

struct GitDiffHunk: Equatable, Identifiable {
    let id: Int
    let header: String
    let lines: [GitDiffLine]
}

struct GitFileDiff: Equatable, Identifiable {
    let id: String
    let path: String
    let oldPath: String?
    let kind: GitFileChangeKind
    let insertions: Int
    let deletions: Int
    let isBinary: Bool
    let isTruncated: Bool
    let summaryNote: String?
    let hunks: [GitDiffHunk]
}

struct GitUntrackedDiffFile: Equatable, Codable {
    let path: String
    let contents: String?
    let note: String?
    let canLoadDetail: Bool
}

struct GitLoadedFileDetail: Equatable, Codable {
    let path: String
    let kind: String
    let textContents: String?
    let imageDataURL: String?
    let truncatedNote: String?
    let errorNote: String?
}

struct GitDiffSnapshot: Equatable {
    let root: URL
    let branch: String
    let rawPatch: String
    let untrackedFiles: [GitUntrackedDiffFile]
    let files: [GitFileDiff]
    let totalInsertions: Int
    let totalDeletions: Int
}

enum GitBranchParser {
    static func parse(
        _ output: String,
        currentBranch: String,
        isDetachedHead: Bool
    ) -> GitBranchList {
        var localBranches: [GitBranch] = []
        var rawRemoteRefs: [(shortName: String, localName: String)] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(
                separator: "\t",
                maxSplits: 3,
                omittingEmptySubsequences: false
            )
            guard fields.count >= 3 else { continue }

            let fullRef = String(fields[0])
            let shortName = String(fields[1])
            let headMarker = String(fields[2])
            let symref = fields.count >= 4 ? String(fields[3]) : ""

            guard symref.isEmpty, !fullRef.hasSuffix("/HEAD"), !shortName.isEmpty else {
                continue
            }

            if fullRef.hasPrefix("refs/heads/") {
                let name = String(fullRef.dropFirst("refs/heads/".count))
                guard !name.isEmpty else { continue }
                let isCurrent = !isDetachedHead && (headMarker == "*" || name == currentBranch)
                localBranches.append(
                    GitBranch(
                        name: name,
                        localName: name,
                        isRemote: false,
                        isCurrent: isCurrent
                    )
                )
            } else if fullRef.hasPrefix("refs/remotes/") {
                let remainder = String(fullRef.dropFirst("refs/remotes/".count))
                guard let slashIndex = remainder.firstIndex(of: "/") else { continue }
                let localName = String(remainder[remainder.index(after: slashIndex)...])
                guard !localName.isEmpty, localName != "HEAD" else { continue }
                rawRemoteRefs.append((shortName: remainder, localName: localName))
            }
        }

        localBranches.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let localNames = Set(localBranches.map(\.name))
        let remoteBranches = rawRemoteRefs
            .filter { !localNames.contains($0.localName) }
            .map {
                GitBranch(
                    name: $0.shortName,
                    localName: $0.localName,
                    isRemote: true,
                    isCurrent: false
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        return GitBranchList(
            currentBranch: currentBranch,
            isDetachedHead: isDetachedHead,
            localBranches: localBranches,
            remoteBranches: remoteBranches
        )
    }
}

enum GitDiffParser {
    static let defaultMaximumLinesPerFile = 1500
    static let defaultMaximumUntrackedBytes = 262_144

    static func parseUnifiedDiff(
        _ output: String,
        maximumLinesPerFile: Int = defaultMaximumLinesPerFile
    ) -> [GitFileDiff] {
        guard !output.isEmpty else { return [] }

        var rawLines = output.components(separatedBy: "\n")
        if rawLines.last == "" {
            rawLines.removeLast()
        }
        for index in rawLines.indices where rawLines[index].hasSuffix("\r") {
            rawLines[index].removeLast()
        }

        struct Builder {
            var path: String
            var oldPath: String?
            var kind: GitFileChangeKind = .modified
            var insertions = 0
            var deletions = 0
            var isBinary = false
            var isTruncated = false
            var hunks: [GitDiffHunk] = []
            var currentHunkHeader: String?
            var currentHunkLines: [GitDiffLine] = []
            var totalRenderedLines = 0
            var oldLine = 1
            var newLine = 1
            var nextLineID = 0

            mutating func flushHunk() {
                guard let header = currentHunkHeader else { return }
                hunks.append(
                    GitDiffHunk(
                        id: hunks.count,
                        header: header,
                        lines: currentHunkLines
                    )
                )
                currentHunkHeader = nil
                currentHunkLines = []
            }

            mutating func build() -> GitFileDiff {
                flushHunk()
                let resolvedOldPath: String?
                if let oldPath, oldPath != path {
                    resolvedOldPath = oldPath
                } else {
                    resolvedOldPath = nil
                }

                let summaryNote: String?
                if isBinary {
                    summaryNote = "Binary file changed"
                } else if hunks.isEmpty {
                    switch kind {
                    case .added:
                        summaryNote = "Empty file added"
                    case .deleted:
                        summaryNote = "Empty file deleted"
                    case .renamed:
                        summaryNote = resolvedOldPath.map { "Renamed from \($0)" } ?? "File renamed"
                    case .copied:
                        summaryNote = resolvedOldPath.map { "Copied from \($0)" } ?? "File copied"
                    default:
                        summaryNote = "File mode or metadata changed"
                    }
                } else {
                    summaryNote = nil
                }

                return GitFileDiff(
                    id: path,
                    path: path,
                    oldPath: resolvedOldPath,
                    kind: kind,
                    insertions: insertions,
                    deletions: deletions,
                    isBinary: isBinary,
                    isTruncated: isTruncated,
                    summaryNote: summaryNote,
                    hunks: hunks
                )
            }
        }

        var files: [GitFileDiff] = []
        var current: Builder?

        for line in rawLines {
            if line.hasPrefix("diff --git ") {
                if var finished = current {
                    files.append(finished.build())
                }
                let parsedPaths = parseDiffGitHeaderPaths(line)
                current = Builder(
                    path: parsedPaths.newPath,
                    oldPath: parsedPaths.oldPath
                )
                continue
            }

            guard current != nil else { continue }

            if current?.currentHunkHeader != nil {
                if line.hasPrefix("@@ ") {
                    current?.flushHunk()
                    if let headerInfo = parseHunkHeader(line) {
                        current?.currentHunkHeader = line
                        current?.oldLine = headerInfo.oldStart
                        current?.newLine = headerInfo.newStart
                    }
                    continue
                }

                if line.hasPrefix("+") {
                    if !line.hasPrefix("+Subproject commit ") {
                        current?.insertions += 1
                    }
                    if let rendered = current?.totalRenderedLines, rendered < maximumLinesPerFile {
                        let lineID = current?.nextLineID ?? 0
                        let newNum = current?.newLine
                        current?.currentHunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .addition,
                                oldLineNumber: nil,
                                newLineNumber: newNum,
                                text: String(line.dropFirst())
                            )
                        )
                        current?.nextLineID += 1
                        current?.totalRenderedLines += 1
                    } else {
                        current?.isTruncated = true
                    }
                    current?.newLine += 1
                } else if line.hasPrefix("-") {
                    if !line.hasPrefix("-Subproject commit ") {
                        current?.deletions += 1
                    }
                    if let rendered = current?.totalRenderedLines, rendered < maximumLinesPerFile {
                        let lineID = current?.nextLineID ?? 0
                        let oldNum = current?.oldLine
                        current?.currentHunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .deletion,
                                oldLineNumber: oldNum,
                                newLineNumber: nil,
                                text: String(line.dropFirst())
                            )
                        )
                        current?.nextLineID += 1
                        current?.totalRenderedLines += 1
                    } else {
                        current?.isTruncated = true
                    }
                    current?.oldLine += 1
                } else if line.hasPrefix("\\") {
                    if let rendered = current?.totalRenderedLines, rendered < maximumLinesPerFile {
                        let lineID = current?.nextLineID ?? 0
                        current?.currentHunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .meta,
                                oldLineNumber: nil,
                                newLineNumber: nil,
                                text: line
                            )
                        )
                        current?.nextLineID += 1
                        current?.totalRenderedLines += 1
                    }
                } else {
                    let contextText = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                    if let rendered = current?.totalRenderedLines, rendered < maximumLinesPerFile {
                        let lineID = current?.nextLineID ?? 0
                        let oldNum = current?.oldLine
                        let newNum = current?.newLine
                        current?.currentHunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .context,
                                oldLineNumber: oldNum,
                                newLineNumber: newNum,
                                text: contextText
                            )
                        )
                        current?.nextLineID += 1
                        current?.totalRenderedLines += 1
                    } else {
                        current?.isTruncated = true
                    }
                    current?.oldLine += 1
                    current?.newLine += 1
                }
                continue
            }

            // File-level metadata headers before first hunk
            if line.hasPrefix("new file mode ") {
                current?.kind = .added
            } else if line.hasPrefix("deleted file mode ") {
                current?.kind = .deleted
            } else if line.hasPrefix("rename from ") {
                current?.kind = .renamed
                current?.oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                current?.kind = .renamed
                current?.path = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("copy from ") {
                current?.kind = .copied
                current?.oldPath = String(line.dropFirst("copy from ".count))
            } else if line.hasPrefix("copy to ") {
                current?.kind = .copied
                current?.path = String(line.dropFirst("copy to ".count))
            } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                current?.isBinary = true
            } else if line.hasPrefix("--- ") {
                let rawOld = String(line.dropFirst(4))
                if rawOld == "/dev/null" {
                    current?.kind = .added
                } else if rawOld.hasPrefix("a/") {
                    current?.oldPath = String(rawOld.dropFirst(2))
                }
            } else if line.hasPrefix("+++ ") {
                let rawNew = String(line.dropFirst(4))
                if rawNew == "/dev/null" {
                    current?.kind = .deleted
                    if let oldPath = current?.oldPath {
                        current?.path = oldPath
                    }
                } else if rawNew.hasPrefix("b/") {
                    current?.path = String(rawNew.dropFirst(2))
                }
            } else if line.hasPrefix("@@ ") {
                if let headerInfo = parseHunkHeader(line) {
                    current?.currentHunkHeader = line
                    current?.oldLine = headerInfo.oldStart
                    current?.newLine = headerInfo.newStart
                }
            }
        }

        if var finished = current {
            files.append(finished.build())
        }

        return files
    }

    static func makeUntrackedFileDiff(
        relativePath: String,
        fileURL: URL,
        maximumBytes: Int = defaultMaximumUntrackedBytes,
        maximumLines: Int = defaultMaximumLinesPerFile
    ) -> GitFileDiff? {
        readUntrackedDiffFile(
            relativePath: relativePath,
            fileURL: fileURL,
            maximumBytes: maximumBytes,
            maximumLines: maximumLines
        )?.summary
    }

    private enum UntrackedFileClassification {
        case empty
        case tooLarge(Int)
        case binary(isPreviewable: Bool)
        case text(String)
    }

    private static func classifyUntrackedFile(
        relativePath: String,
        fileURL: URL,
        maximumBytes: Int
    ) -> UntrackedFileClassification? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        if fileSize == 0 {
            return .empty
        }
        if fileSize > maximumBytes {
            return .tooLarge(fileSize)
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        if data.prefix(8192).contains(0) {
            return .binary(isPreviewable: Self.imageMIMEType(forPath: relativePath) != nil)
        }

        return .text(String(decoding: data, as: UTF8.self))
    }

    private static func normalizedLines(from text: String) -> [String] {
        var rawLines = text.components(separatedBy: "\n")
        if rawLines.last == "" {
            rawLines.removeLast()
        }
        for index in rawLines.indices where rawLines[index].hasSuffix("\r") {
            rawLines[index].removeLast()
        }
        return rawLines
    }

    /// Returns the number of inserted lines for an untracked file using the same rules as `readUntrackedDiffFile`,
    /// or `nil` if the path is a directory or unreadable.
    static func untrackedFileInsertionCount(
        relativePath: String,
        fileURL: URL,
        maximumBytes: Int = defaultMaximumUntrackedBytes
    ) -> Int? {
        guard let classification = classifyUntrackedFile(
            relativePath: relativePath,
            fileURL: fileURL,
            maximumBytes: maximumBytes
        ) else {
            return nil
        }
        switch classification {
        case .empty, .tooLarge, .binary:
            return 0
        case .text(let text):
            return normalizedLines(from: text).count
        }
    }

    static func readUntrackedDiffFile(
        relativePath: String,
        fileURL: URL,
        maximumBytes: Int = defaultMaximumUntrackedBytes,
        maximumLines: Int = defaultMaximumLinesPerFile
    ) -> (untracked: GitUntrackedDiffFile, summary: GitFileDiff)? {
        guard let classification = classifyUntrackedFile(
            relativePath: relativePath,
            fileURL: fileURL,
            maximumBytes: maximumBytes
        ) else {
            return nil
        }

        switch classification {
        case .empty:
            let note = "Empty untracked file"
            return (
                GitUntrackedDiffFile(path: relativePath, contents: "", note: note, canLoadDetail: false),
                GitFileDiff(
                    id: relativePath,
                    path: relativePath,
                    oldPath: nil,
                    kind: .untracked,
                    insertions: 0,
                    deletions: 0,
                    isBinary: false,
                    isTruncated: false,
                    summaryNote: note,
                    hunks: []
                )
            )

        case .tooLarge(let fileSize):
            let note = "Large untracked file (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))"
            return (
                GitUntrackedDiffFile(path: relativePath, contents: nil, note: note, canLoadDetail: true),
                GitFileDiff(
                    id: relativePath,
                    path: relativePath,
                    oldPath: nil,
                    kind: .untracked,
                    insertions: 0,
                    deletions: 0,
                    isBinary: false,
                    isTruncated: true,
                    summaryNote: note,
                    hunks: []
                )
            )

        case .binary(let isPreviewable):
            let note = "Binary untracked file"
            return (
                GitUntrackedDiffFile(
                    path: relativePath,
                    contents: nil,
                    note: note,
                    canLoadDetail: isPreviewable
                ),
                GitFileDiff(
                    id: relativePath,
                    path: relativePath,
                    oldPath: nil,
                    kind: .untracked,
                    insertions: 0,
                    deletions: 0,
                    isBinary: true,
                    isTruncated: false,
                    summaryNote: note,
                    hunks: []
                )
            )

        case .text(let text):
            let rawLines = normalizedLines(from: text)
            let totalLines = rawLines.count
            let isTruncated = totalLines > maximumLines
            let visibleSlice = rawLines.prefix(maximumLines)
            let diffLines = visibleSlice.enumerated().map { index, content in
                GitDiffLine(
                    id: index,
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: index + 1,
                    text: content
                )
            }

            let hunk = GitDiffHunk(
                id: 0,
                header: "@@ -0,0 +1,\(totalLines) @@",
                lines: diffLines
            )

            let truncatedContents = isTruncated
                ? visibleSlice.joined(separator: "\n") + "\n"
                : text

            return (
                GitUntrackedDiffFile(
                    path: relativePath,
                    contents: truncatedContents,
                    note: nil,
                    canLoadDetail: false
                ),
                GitFileDiff(
                    id: relativePath,
                    path: relativePath,
                    oldPath: nil,
                    kind: .untracked,
                    insertions: totalLines,
                    deletions: 0,
                    isBinary: false,
                    isTruncated: isTruncated,
                    summaryNote: nil,
                    hunks: [hunk]
                )
            )
        }
    }

    static let defaultMaximumDetailBytes = 2_097_152
    static let defaultMaximumImagePreviewBytes = 10_485_760

    static func imageMIMEType(forPath path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "bmp":
            return "image/bmp"
        case "ico":
            return "image/x-icon"
        default:
            return nil
        }
    }

    static func loadFileDetailFromDisk(
        relativePath: String,
        kind: String,
        fileURL: URL,
        maximumDetailBytes: Int = defaultMaximumDetailBytes,
        maximumImageBytes: Int = defaultMaximumImagePreviewBytes
    ) -> GitLoadedFileDetail? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)

        if let mimeType = imageMIMEType(forPath: relativePath),
           mimeType != "image/svg+xml" {
            guard fileSize <= maximumImageBytes,
                  let data = try? Data(contentsOf: fileURL)
            else {
                return GitLoadedFileDetail(
                    path: relativePath,
                    kind: kind,
                    textContents: nil,
                    imageDataURL: nil,
                    truncatedNote: nil,
                    errorNote: "Image too large to preview (\(formattedSize))"
                )
            }
            return GitLoadedFileDetail(
                path: relativePath,
                kind: kind,
                textContents: nil,
                imageDataURL: "data:\(mimeType);base64,\(data.base64EncodedString())",
                truncatedNote: nil,
                errorNote: nil
            )
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: maximumDetailBytes)) ?? Data()
        if data.prefix(8192).contains(0) {
            return GitLoadedFileDetail(
                path: relativePath,
                kind: kind,
                textContents: nil,
                imageDataURL: nil,
                truncatedNote: nil,
                errorNote: "Binary file (\(formattedSize)) — text preview unavailable"
            )
        }

        let cleanData = trimIncompleteUTF8Tail(data, wasTruncated: fileSize > data.count)
        let text = String(decoding: cleanData, as: UTF8.self)
        let truncatedNote = fileSize > data.count
            ? "Showing first \(ByteCountFormatter.string(fromByteCount: Int64(cleanData.count), countStyle: .file)) of \(formattedSize)"
            : nil

        return GitLoadedFileDetail(
            path: relativePath,
            kind: kind,
            textContents: text,
            imageDataURL: nil,
            truncatedNote: truncatedNote,
            errorNote: nil
        )
    }

    private static func trimIncompleteUTF8Tail(_ data: Data, wasTruncated: Bool) -> Data {
        guard wasTruncated, !data.isEmpty else { return data }
        var end = data.count
        let minScan = max(0, data.count - 4)
        while end > minScan {
            let byte = data[end - 1]
            if byte & 0b1000_0000 == 0 {
                return data
            }
            if byte & 0b1100_0000 == 0b1100_0000 {
                let expectedLength: Int
                if byte & 0b1110_0000 == 0b1100_0000 {
                    expectedLength = 2
                } else if byte & 0b1111_0000 == 0b1110_0000 {
                    expectedLength = 3
                } else {
                    expectedLength = 4
                }
                let actualLength = data.count - (end - 1)
                return actualLength >= expectedLength ? data : data.prefix(end - 1)
            }
            end -= 1
        }
        return data
    }

    private static func parseDiffGitHeaderPaths(_ line: String) -> (oldPath: String, newPath: String) {
        let remainder = String(line.dropFirst("diff --git ".count))
        let chars = Array(remainder)

        // Check symmetric "a/<path> b/<path>" first so paths containing spaces parse cleanly.
        if chars.count >= 5,
           chars.count % 2 == 1,
           remainder.hasPrefix("a/") {
            let mid = (chars.count - 1) / 2
            if chars[mid] == " ",
               mid + 2 < chars.count,
               chars[mid + 1] == "b",
               chars[mid + 2] == "/" {
                let left = String(chars[2..<mid])
                let right = String(chars[(mid + 3)...])
                if left == right {
                    return (left, right)
                }
            }
        }

        if let range = remainder.range(of: " b/") {
            let rawOld = String(remainder[..<range.lowerBound])
            let oldPath = rawOld.hasPrefix("a/") ? String(rawOld.dropFirst(2)) : rawOld
            let newPath = String(remainder[range.upperBound...])
            return (oldPath, newPath)
        }

        return (remainder, remainder)
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int)? {
        guard line.hasPrefix("@@ "),
              let endRange = line.range(of: " @@", range: line.index(line.startIndex, offsetBy: 3)..<line.endIndex)
        else {
            return nil
        }

        let coords = line[line.index(line.startIndex, offsetBy: 3)..<endRange.lowerBound]
        let parts = coords.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let oldPart = parts[0].dropFirst()
        let newPart = parts[1].dropFirst()
        let oldStart = Int(oldPart.split(separator: ",").first ?? "") ?? 1
        let newStart = Int(newPart.split(separator: ",").first ?? "") ?? 1
        return (oldStart, newStart)
    }
}
