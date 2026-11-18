import AppKit
import SwiftUI

struct TerminalTitleBarView: View {
    @ObservedObject var session: TerminalSession
    let onSelect: () -> Void
    let onRequestBranches: () async -> GitBranchList?
    let onSelectBranch: (GitBranch) -> Void
    let onToggleDiffs: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(displayPath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColermTheme.terminalTitleText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .overlay(alignment: .bottomLeading) {
                        if session.isActive {
                            Capsule()
                                .fill(TerminalAccent.forSession(session.id).color)
                                .frame(height: 2)
                                .offset(y: 8)
                        }
                    }

                Spacer(minLength: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            if let git = session.metadata.git {
                GitSummaryView(
                    git: git,
                    isDiffSidebarVisible: session.isDiffSidebarVisible,
                    onSelectColumn: onSelect,
                    onRequestBranches: onRequestBranches,
                    onSelectBranch: onSelectBranch,
                    onToggleDiffs: onToggleDiffs
                )
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let isDiffSidebarVisible: Bool
    let onSelectColumn: () -> Void
    let onRequestBranches: () async -> GitBranchList?
    let onSelectBranch: (GitBranch) -> Void
    let onToggleDiffs: () -> Void

    @StateObject private var branchAnchor = MenuAnchorBox()
    @State private var isBranchHovered = false
    @State private var isDiffHovered = false

    private var showsDiffToggle: Bool {
        git.changedFiles > 0 || isDiffSidebarVisible
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: presentBranchDropdown) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(git.branch)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .opacity(0.72)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    isBranchHovered ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .background(MenuAnchorRepresentable(box: branchAnchor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isBranchHovered = $0 }
            .help("Branch: \(git.branch) — Click to switch branch")
            .accessibilityLabel("Switch Git Branch, current \(git.branch)")

            if showsDiffToggle {
                Button(action: onToggleDiffs) {
                    HStack(spacing: 5) {
                        if isDiffSidebarVisible {
                            Image(systemName: "doc.text")
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.text")
                                Text("\(git.changedFiles)")
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(git.changedFiles) changed files")

                            if git.insertions > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "plus")
                                    Text("\(git.insertions)")
                                }
                                .foregroundStyle(.green)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(git.insertions) insertions")
                            }

                            if git.deletions > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "minus")
                                    Text("\(git.deletions)")
                                }
                                .foregroundStyle(.red)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(git.deletions) deletions")
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(diffButtonBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        if isDiffSidebarVisible {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isDiffHovered = $0 }
                .help(diffHelp)
                .accessibilityLabel(isDiffSidebarVisible ? "Hide Diffs" : "Show Diffs")
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(ColermTheme.terminalTitleText)
    }

    private var diffButtonBackground: Color {
        if isDiffSidebarVisible {
            return Color.primary.opacity(isDiffHovered ? 0.17 : 0.12)
        }
        return isDiffHovered ? Color.primary.opacity(0.08) : .clear
    }

    private var diffHelp: String {
        let action = isDiffSidebarVisible ? "Click to hide diffs" : "Click to show diffs"
        guard git.changedFiles > 0 else { return action }
        return "\(git.changedFiles) changed · +\(git.insertions) −\(git.deletions) — \(action)"
    }

    private func presentBranchDropdown() {
        onSelectColumn()
        Task { @MainActor in
            guard let branchList = await onRequestBranches(),
                  let anchorView = branchAnchor.view,
                  anchorView.window != nil
            else { return }

            BranchMenuPresenter.present(
                branchList: branchList,
                anchorView: anchorView,
                onSelectBranch: onSelectBranch
            )
        }
    }
}

@MainActor
private final class MenuAnchorBox: ObservableObject {
    weak var view: NSView?
}

private struct MenuAnchorRepresentable: NSViewRepresentable {
    @ObservedObject var box: MenuAnchorBox

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        box.view = nsView
    }
}

@MainActor
enum BranchMenuPresenter {
    static func present(
        branchList: GitBranchList,
        anchorView: NSView,
        onSelectBranch: @escaping (GitBranch) -> Void
    ) {
        let menu = buildMenu(from: branchList, onSelectBranch: onSelectBranch)
        let origin = NSPoint(x: 0, y: anchorView.isFlipped ? anchorView.bounds.height + 3 : -3)
        menu.popUp(positioning: nil, at: origin, in: anchorView)
    }

    static func buildMenu(
        from branchList: GitBranchList,
        onSelectBranch: @escaping (GitBranch) -> Void
    ) -> NSMenu {
        let menu = NSMenu(title: "Switch Branch")
        menu.autoenablesItems = false
        menu.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        if branchList.isDetachedHead {
            let detachedItem = NSMenuItem(
                title: "Detached HEAD",
                action: nil,
                keyEquivalent: ""
            )
            detachedItem.isEnabled = false
            detachedItem.state = .on
            menu.addItem(detachedItem)

            if !branchList.localBranches.isEmpty || !branchList.remoteBranches.isEmpty {
                menu.addItem(.separator())
            }
        } else if branchList.localBranches.isEmpty {
            let unbornItem = NSMenuItem(
                title: "\(branchList.currentBranch) (no commits yet)",
                action: nil,
                keyEquivalent: ""
            )
            unbornItem.isEnabled = false
            unbornItem.state = .on
            menu.addItem(unbornItem)
        }

        for branch in branchList.localBranches {
            menu.addItem(makeBranchItem(for: branch, onSelectBranch: onSelectBranch))
        }

        if !branchList.remoteBranches.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let submenu = NSMenu(title: "Remote Branches")
            submenu.autoenablesItems = false
            submenu.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            for remoteBranch in branchList.remoteBranches {
                submenu.addItem(makeBranchItem(for: remoteBranch, onSelectBranch: onSelectBranch))
            }

            let remoteParent = NSMenuItem(
                title: "Remote Branches",
                action: nil,
                keyEquivalent: ""
            )
            remoteParent.isEnabled = true
            remoteParent.submenu = submenu
            menu.addItem(remoteParent)
        }

        return menu
    }

    private static func makeBranchItem(
        for branch: GitBranch,
        onSelectBranch: @escaping (GitBranch) -> Void
    ) -> NSMenuItem {
        let target = BranchMenuTarget(branch: branch, onSelectBranch: onSelectBranch)
        let item = NSMenuItem(
            title: branch.name,
            action: #selector(BranchMenuTarget.selectBranch(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = target
        item.isEnabled = true
        item.state = (!branch.isRemote && branch.isCurrent) ? .on : .off
        return item
    }
}

@MainActor
private final class BranchMenuTarget: NSObject {
    let branch: GitBranch
    let onSelectBranch: (GitBranch) -> Void

    init(branch: GitBranch, onSelectBranch: @escaping (GitBranch) -> Void) {
        self.branch = branch
        self.onSelectBranch = onSelectBranch
    }

    @objc func selectBranch(_: NSMenuItem) {
        guard branch.isRemote || !branch.isCurrent else { return }
        onSelectBranch(branch)
    }
}
