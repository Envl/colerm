import SwiftUI

struct WorkspaceTabBarView: View {
    @ObservedObject var store: WorkspaceStore

    @State private var draggedSessionID: TerminalSessionID?
    @State private var previewOrder: [TerminalSessionID] = []
    @State private var tabFrames: [TerminalSessionID: CGRect] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0

    private var displayedSessions: [TerminalSession] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.id, $0) })
        let order = draggedSessionID == nil ? store.sessions.map(\.id) : previewOrder
        return order.compactMap { sessionsByID[$0] }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(displayedSessions) { session in
                        WorkspaceTab(
                            session: session,
                            isSelected: store.selectedSessionID == session.id,
                            onSelect: { store.select(session.id) },
                            onClose: { _ = store.closeColumn(session.id, confirm: false) },
                            onNewTabLeft: { store.addColumn(toLeftOf: session.id) },
                            onNewTabRight: { store.addColumn(toRightOf: session.id) },
                            onDragChanged: { updateDrag(session.id, value: $0) },
                            onDragEnded: { finishDrag(session.id) }
                        )
                        .id(session.id)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WorkspaceTabFramePreferenceKey.self,
                                    value: [session.id: geometry.frame(in: .named("workspace-tab-strip"))]
                                )
                            }
                        }
                        .offset(x: draggedSessionID == session.id ? dragOffset : 0)
                        .zIndex(draggedSessionID == session.id ? 1 : 0)
                        .shadow(
                            color: .black.opacity(draggedSessionID == session.id ? 0.20 : 0),
                            radius: 7,
                            y: 2
                        )
                    }

                    AddWorkspaceTab {
                        store.addColumn()
                    }
                }
                .coordinateSpace(name: "workspace-tab-strip")
                .onPreferenceChange(WorkspaceTabFramePreferenceKey.self) { tabFrames = $0 }
            }
            .onChange(of: store.selectedSessionID) { _, sessionID in
                guard let sessionID else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(sessionID, anchor: .center)
                }
            }
            .onAppear {
                previewOrder = store.sessions.map(\.id)
            }
            .onChange(of: store.sessions.map(\.id)) { _, sessionIDs in
                guard draggedSessionID == nil else { return }
                previewOrder = sessionIDs
            }
        }
        .frame(height: 36)
        .background(ColermTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(height: 1)
        }
    }

    private func updateDrag(_ sessionID: TerminalSessionID, value: DragGesture.Value) {
        if draggedSessionID == nil {
            draggedSessionID = sessionID
            previewOrder = store.sessions.map(\.id)
            dragOffset = 0
            lastDragTranslation = 0
        }
        guard draggedSessionID == sessionID else { return }

        dragOffset += value.translation.width - lastDragTranslation
        lastDragTranslation = value.translation.width
        swapWithCrossedNeighbor(sessionID)
    }

    private func swapWithCrossedNeighbor(_ sessionID: TerminalSessionID) {
        guard let index = previewOrder.firstIndex(of: sessionID),
              let draggedFrame = tabFrames[sessionID]
        else { return }

        let draggedCenter = draggedFrame.midX + dragOffset
        if index > 0,
           let neighborFrame = tabFrames[previewOrder[index - 1]],
           draggedCenter < neighborFrame.midX {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                previewOrder.swapAt(index, index - 1)
                dragOffset += neighborFrame.width
            }
        } else if index < previewOrder.count - 1,
                  let neighborFrame = tabFrames[previewOrder[index + 1]],
                  draggedCenter > neighborFrame.midX {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                previewOrder.swapAt(index, index + 1)
                dragOffset -= neighborFrame.width
            }
        }
    }

    private func finishDrag(_ sessionID: TerminalSessionID) {
        guard draggedSessionID == sessionID,
              let sourceIndex = store.sessions.firstIndex(where: { $0.id == sessionID }),
              let destinationIndex = previewOrder.firstIndex(of: sessionID)
        else {
            resetDrag()
            return
        }

        if sourceIndex != destinationIndex {
            let insertionIndex = destinationIndex > sourceIndex
                ? destinationIndex + 1
                : destinationIndex
            _ = store.moveColumn(sessionID, toInsertionIndex: insertionIndex)
        }
        resetDrag()
    }

    private func resetDrag() {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
            dragOffset = 0
            draggedSessionID = nil
        }
        lastDragTranslation = 0
        previewOrder = store.sessions.map(\.id)
    }
}

private struct WorkspaceTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TerminalSessionID: CGRect] = [:]

    static func reduce(
        value: inout [TerminalSessionID: CGRect],
        nextValue: () -> [TerminalSessionID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct WorkspaceTab: View {
    @ObservedObject var session: TerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onNewTabLeft: () -> Void
    let onNewTabRight: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void

    @State private var isHovered = false

    private var accent: Color {
        TerminalAccent.forSession(session.id).color
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: accent.opacity(0.8), radius: 5)

                Text(projectFolderName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? ColermTheme.primaryText : ColermTheme.secondaryText)
                    .lineLimit(1)

                if let branch = session.metadata.git?.branch {
                    Text(branch)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(ColermTheme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 26)
            }
            .padding(.horizontal, 18)
            .frame(minWidth: 170, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("workspace-tab-strip"))
                    .onChanged(onDragChanged)
                    .onEnded { _ in onDragEnded() }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect() }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovered ? ColermTheme.secondaryText : ColermTheme.tertiaryText)
            .padding(.trailing, 7)
            .help("Close Terminal")
        }
        .frame(height: 36)
        .background(tabBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Capsule()
                    .fill(accent)
                    .frame(height: 2)
                    .padding(.horizontal, 18)
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("New Tab to the Left", systemImage: "arrow.left.to.line", action: onNewTabLeft)
            Button("New Tab to the Right", systemImage: "arrow.right.to.line", action: onNewTabRight)
        }
        .accessibilityElement(children: .contain)
    }

    private var tabBackground: Color {
        if isSelected {
            return ColermTheme.selectedTab
        }
        return isHovered ? ColermTheme.primaryText.opacity(0.045) : .clear
    }

    private var projectFolderName: String {
        WorkspaceTabTitle.folderName(
            cwd: session.cwd,
            gitRoot: session.metadata.git?.root
        )
    }
}

private struct AddWorkspaceTab: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 48, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? ColermTheme.primaryText : ColermTheme.secondaryText)
        .background(isHovered ? ColermTheme.primaryText.opacity(0.045) : .clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(width: 1)
        }
        .onHover { isHovered = $0 }
        .help("New Terminal")
        .accessibilityLabel("New Terminal")
    }
}
