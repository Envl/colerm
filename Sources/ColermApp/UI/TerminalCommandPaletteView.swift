import SwiftUI

struct TerminalCommandPaletteView: View {
    @ObservedObject var store: WorkspaceStore
    let presentationID: UUID
    let activate: (TerminalSessionID) -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selectedID: TerminalSessionID?
    @State private var focusRequest = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TerminalPaletteSearchField(
                    text: $query,
                    focusRequest: focusRequest,
                    onMoveUp: { moveSelection(by: -1) },
                    onMoveDown: { moveSelection(by: 1) },
                    onSubmit: activateSelection,
                    onCancel: dismiss
                )
                .frame(height: 26)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                ColermTheme.paletteRaised,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            }
            .padding(10)

            paletteDivider

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Terminals",
                    systemImage: "terminal",
                    description: Text("No open terminal matches this search.")
                )
                .foregroundStyle(ColermTheme.paletteSecondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(filteredItems) { item in
                                Button {
                                    activate(item.id)
                                } label: {
                                    TerminalPaletteRow(
                                        item: item,
                                        isSelected: item.id == selectedID
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedID) {
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }

            paletteDivider

            HStack {
                footerHint(keys: "↑↓", label: "Navigate")
                Spacer()
                footerHint(keys: "↵", label: "Jump")
                footerHint(keys: "Esc", label: "Close")
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(ColermTheme.paletteFooter)
        }
        .frame(
            width: TerminalCommandPaletteLayout.cardSize.width,
            height: TerminalCommandPaletteLayout.cardSize.height
        )
        .background(ColermTheme.paletteCanvas)
        .clipShape(RoundedRectangle(cornerRadius: TerminalCommandPaletteLayout.cornerRadius))
        .onAppear {
            query = ""
            selectedID = store.selectedSessionID ?? filteredItems.first?.id
            focusRequest = UUID()
        }
        .onChange(of: query) {
            selectedID = filteredItems.first?.id
        }
        .onChange(of: itemIDs) {
            if !filteredItems.contains(where: { $0.id == selectedID }) {
                selectedID = filteredItems.first?.id
            }
        }
        .id(presentationID)
    }

    private var items: [TerminalPaletteItem] {
        store.sessions.enumerated().map { index, session in
            TerminalPaletteItem(
                id: session.id,
                index: index + 1,
                title: session.displayTitle,
                path: Self.displayPath(session.cwd)
            )
        }
    }

    private var filteredItems: [TerminalPaletteItem] {
        TerminalPaletteSearch.filter(items, query: query)
    }

    private var itemIDs: [TerminalSessionID] {
        filteredItems.map(\.id)
    }

    private var paletteDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
    }

    private func footerHint(keys: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(ColermTheme.palettePrimaryText)
                .padding(.horizontal, 5)
                .frame(height: 19)
                .background(ColermTheme.paletteRaised, in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .font(.caption)
                .foregroundStyle(ColermTheme.paletteSecondaryText)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            filteredItems.firstIndex(where: { $0.id == id })
        } ?? 0
        let newIndex = (currentIndex + offset + filteredItems.count) % filteredItems.count
        selectedID = filteredItems[newIndex].id
    }

    private func activateSelection() {
        guard let selectedID = selectedID ?? filteredItems.first?.id else { return }
        activate(selectedID)
    }

    private static func displayPath(_ url: URL?) -> String {
        guard let path = url?.path else { return "Starting shell…" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct TerminalPaletteRow: View {
    let item: TerminalPaletteItem
    let isSelected: Bool

    private var accent: Color {
        TerminalAccent.forSession(item.id).color
    }

    var body: some View {
        HStack(spacing: 11) {
            Text("\(item.index)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    isSelected ? TerminalAccent.forSession(item.id).contrastingText : accent
                )
                .frame(width: 24, height: 22)
                .background(
                    isSelected
                        ? accent
                        : accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 5)
                )

            Text(item.path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ColermTheme.palettePrimaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if isSelected {
                Text("↵")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            isSelected ? accent.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(accent)
                    .frame(width: 2, height: 20)
            }
        }
        .contentShape(Rectangle())
    }
}
