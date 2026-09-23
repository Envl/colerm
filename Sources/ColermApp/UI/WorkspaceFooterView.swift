import SwiftUI

struct WorkspaceFooterView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var shortcutSettings: KeyboardShortcutSettings

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(activityColor)
                .frame(width: 5, height: 5)
                .shadow(color: activityColor.opacity(activeCount > 0 ? 0.8 : 0), radius: 4.5)

            HStack(spacing: 0) {
                Text(terminalCountText)

                if activeCount > 0 {
                    Text(" · ")

                    Menu {
                        ForEach(runningSessions) { session in
                            Button {
                                store.select(session.id)
                            } label: {
                                Text(tabTitle(for: session))
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                            .fixedSize(horizontal: true, vertical: true)
                        }
                    } label: {
                        Text("\(activeCount) running")
                            .foregroundStyle(ColermTheme.secondaryText)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize(horizontal: true, vertical: true)
                    .help("Jump to a running terminal")
                }
            }

            Spacer()

            Text(paletteShortcut.displayComponents.joined(separator: " "))
                .foregroundStyle(ColermTheme.tertiaryText)

            Text("Command palette")
                .foregroundStyle(ColermTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(ColermTheme.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColermTheme.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(height: 1)
        }
    }

    private var activeCount: Int {
        runningSessions.count
    }

    private var runningSessions: [TerminalSession] {
        store.sessions.filter(\.isForegroundCommandRunning)
    }

    private var activityColor: Color {
        activeCount > 0
            ? Color(nsColor: .systemGreen)
            : ColermTheme.tertiaryText
    }

    private var terminalCountText: String {
        let terminalWord = store.sessions.count == 1 ? "terminal" : "terminals"
        return "\(store.sessions.count) \(terminalWord)"
    }

    private func tabTitle(for session: TerminalSession) -> String {
        WorkspaceTabTitle.folderName(
            cwd: session.cwd,
            gitRoot: session.metadata.git?.root
        )
    }

    private var paletteShortcut: KeyboardShortcut {
        shortcutSettings.shortcut(for: .commandPalette)
    }
}
