import SwiftUI

struct WorkspaceTabBarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var layoutSettings: WorkspaceLayoutSettings
    let onSelectSession: (TerminalSessionID) -> Void

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

    private var isVertical: Bool {
        layoutSettings.isVerticalTabsEnabled
    }

    private var verticalTabsWidth: CGFloat {
        layoutSettings.verticalTabsWidth
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
                Group {
                    if isVertical {
                        VStack(spacing: 0) {
                            tabItems
                        }
                    } else {
                        HStack(spacing: 0) {
                            tabItems
                        }
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
            .onChange(of: layoutSettings.isVerticalTabsEnabled) { _, _ in
                resetDrag()
                guard let sessionID = store.selectedSessionID else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(sessionID, anchor: .center)
                    }
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
        .frame(
            width: isVertical ? verticalTabsWidth : nil,
            height: isVertical ? nil : WorkspaceLayoutMetrics.tabHeight
        )
        .background(ColermTheme.chrome)
        .overlay(alignment: isVertical ? .trailing : .bottom) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
        }
    }

    @ViewBuilder
    private var tabItems: some View {
        ForEach(displayedSessions) { session in
            WorkspaceTab(
                session: session,
                isSelected: store.selectedSessionID == session.id,
                isVertical: isVertical,
                verticalTabsWidth: verticalTabsWidth,
                onSelect: { onSelectSession(session.id) },
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
            .offset(
                x: isVertical || draggedSessionID != session.id ? 0 : dragOffset,
                y: isVertical && draggedSessionID == session.id ? dragOffset : 0
            )
            .zIndex(draggedSessionID == session.id ? 1 : 0)
            .shadow(
                color: .black.opacity(draggedSessionID == session.id ? 0.20 : 0),
                radius: 7,
                x: isVertical ? 2 : 0,
                y: isVertical ? 0 : 2
            )
        }

        AddWorkspaceTab(isVertical: isVertical, verticalTabsWidth: verticalTabsWidth) {
            store.addColumn()
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

        let translation = isVertical ? value.translation.height : value.translation.width
        dragOffset += translation - lastDragTranslation
        lastDragTranslation = translation
        swapWithCrossedNeighbor(sessionID)
    }

    private func swapWithCrossedNeighbor(_ sessionID: TerminalSessionID) {
        guard let index = previewOrder.firstIndex(of: sessionID),
              let draggedFrame = tabFrames[sessionID]
        else { return }

        let draggedCenter = (isVertical ? draggedFrame.midY : draggedFrame.midX) + dragOffset
        if index > 0,
           let neighborFrame = tabFrames[previewOrder[index - 1]],
           draggedCenter < (isVertical ? neighborFrame.midY : neighborFrame.midX) {
            let neighborExtent = isVertical ? neighborFrame.height : neighborFrame.width
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                previewOrder.swapAt(index, index - 1)
                dragOffset += neighborExtent
            }
        } else if index < previewOrder.count - 1,
                  let neighborFrame = tabFrames[previewOrder[index + 1]],
                  draggedCenter > (isVertical ? neighborFrame.midY : neighborFrame.midX) {
            let neighborExtent = isVertical ? neighborFrame.height : neighborFrame.width
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                previewOrder.swapAt(index, index + 1)
                dragOffset -= neighborExtent
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
    let isVertical: Bool
    let verticalTabsWidth: CGFloat
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
            .frame(
                minWidth: isVertical ? 0 : 170,
                maxWidth: isVertical ? .infinity : nil,
                maxHeight: .infinity
            )
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
        .frame(
            width: isVertical ? verticalTabsWidth : nil,
            height: WorkspaceLayoutMetrics.tabHeight
        )
        .background(tabBackground)
        .overlay(alignment: isVertical ? .bottom : .trailing) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(width: isVertical ? nil : 1, height: isVertical ? 1 : nil)
        }
        .overlay(alignment: isVertical ? .leading : .bottom) {
            if isSelected {
                Capsule()
                    .fill(accent)
                    .frame(width: isVertical ? 2 : nil, height: isVertical ? 20 : 2)
                    .padding(.horizontal, isVertical ? 0 : 18)
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
    let isVertical: Bool
    let verticalTabsWidth: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .frame(
                    width: isVertical ? verticalTabsWidth : 48,
                    height: WorkspaceLayoutMetrics.tabHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? ColermTheme.primaryText : ColermTheme.secondaryText)
        .background(isHovered ? ColermTheme.primaryText.opacity(0.045) : .clear)
        .overlay(alignment: isVertical ? .bottom : .trailing) {
            Rectangle()
                .fill(ColermTheme.separator)
                .frame(width: isVertical ? nil : 1, height: isVertical ? 1 : nil)
        }
        .onHover { isHovered = $0 }
        .help("New Terminal")
        .accessibilityLabel("New Terminal")
    }
}
