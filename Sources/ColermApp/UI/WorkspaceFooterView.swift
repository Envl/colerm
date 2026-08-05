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

            Text(terminalSummary)

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
        store.sessions.count(where: \.isForegroundCommandRunning)
    }

    private var activityColor: Color {
        activeCount > 0
            ? Color(nsColor: .systemGreen)
            : ColermTheme.tertiaryText
    }

    private var terminalSummary: String {
        let terminalWord = store.sessions.count == 1 ? "terminal" : "terminals"
        return "\(store.sessions.count) \(terminalWord) · \(activeCount) running"
    }

    private var paletteShortcut: KeyboardShortcut {
        shortcutSettings.shortcut(for: .commandPalette)
    }
}
