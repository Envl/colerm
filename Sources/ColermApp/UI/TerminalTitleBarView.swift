import SwiftUI

struct TerminalTitleBarView: View {
    @ObservedObject var session: TerminalSession
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(displayPath)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let git = session.metadata.git {
                GitSummaryView(git: git)
            }

        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(ColermTheme.terminalTitle)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var displayPath: String {
        guard let path = session.cwd?.path else { return "Starting shell…" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct GitSummaryView: View {
    let git: GitMetadata

    var body: some View {
        HStack(spacing: 7) {
            Label(git.branch, systemImage: "arrow.triangle.branch")
                .lineLimit(1)

            if git.changedFiles > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "doc.text")
                    Text("\(git.changedFiles)")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(git.changedFiles) changed files")
            }
            if git.insertions > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                    Text("\(git.insertions)")
                }
                    .foregroundStyle(.green)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(git.insertions) insertions")
            }
            if git.deletions > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "minus")
                    Text("\(git.deletions)")
                }
                    .foregroundStyle(.red)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(git.deletions) deletions")
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .help(gitHelp)
    }

    private var gitHelp: String {
        guard git.changedFiles > 0 else { return "Branch: \(git.branch)" }
        return "Branch: \(git.branch) · \(git.changedFiles) changed · +\(git.insertions) −\(git.deletions)"
    }
}
