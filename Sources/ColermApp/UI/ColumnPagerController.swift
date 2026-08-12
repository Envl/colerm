import AppKit
import SwiftUI

@MainActor
final class ColumnPagerController: NSViewController {
    private static let splitterLayoutWidth: CGFloat = 1
    private static let splitterHitWidth: CGFloat = 5
    private static let minimumAddTerminalWidth: CGFloat = 48

    private let store: WorkspaceStore
    private let shortcutSettings: KeyboardShortcutSettings
    private let onOpenSettings: () -> Void
    private let scrollView = NSScrollView(frame: .zero)
    private let documentView = NSView(frame: .zero)
    private let addTerminalView = AddTerminalView(frame: .zero)
    private var columnViews: [TerminalSessionID: TerminalColumnView] = [:]
    private var splitterViews: [TerminalSessionID: TerminalSplitterView] = [:]
    private var selectionUpdate: DispatchWorkItem?
    private var lastSynchronizedSessionID: TerminalSessionID?
    private var lastSessionOrder: [TerminalSessionID] = []
    private var scrollAnimationGeneration = 0
    private var isProgrammaticScroll = false
    private var suppressSelectionScroll = false

    init(
        store: WorkspaceStore,
        shortcutSettings: KeyboardShortcutSettings,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.shortcutSettings = shortcutSettings
        self.onOpenSettings = onOpenSettings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ColumnPagerController does not support NSCoder construction")
    }

    override func loadView() {
        view = ThemedBackgroundView(color: ColermTheme.workspaceBackgroundNS)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true

        addTerminalView.onCreate = { [weak self] in
            self?.store.addColumn()
        }
        documentView.addSubview(addTerminalView)

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutDocument()
    }

    func synchronize() {
        let sessionOrder = store.sessions.map(\.id)
        let orderChanged = sessionOrder != lastSessionOrder
        lastSessionOrder = sessionOrder

        removeStaleViews()
        buildMissingViews()
        layoutDocument()

        let selectionChanged = lastSynchronizedSessionID != store.selectedSessionID
        if selectionChanged {
            lastSynchronizedSessionID = store.selectedSessionID
        }
        if (selectionChanged && !suppressSelectionScroll) || orderChanged {
            scrollToSelectedColumn()
        }
        if selectionChanged {
            focusSelectedSurface()
        }
        suppressSelectionScroll = false
        updateSurfaceVisibility()
    }

    func previousColumn() {
        selectColumn(at: currentIndex - 1)
    }

    func nextColumn() {
        selectColumn(at: currentIndex + 1)
    }

    private var currentIndex: Int {
        guard let selectedID = store.selectedSessionID,
              let index = store.sessions.firstIndex(where: { $0.id == selectedID })
        else { return 0 }
        return index
    }

    private func removeStaleViews() {
        let activeIDs = Set(store.sessions.map(\.id))
        let staleColumnIDs = columnViews.keys.filter { !activeIDs.contains($0) }
        for sessionID in staleColumnIDs {
            columnViews.removeValue(forKey: sessionID)?.removeFromSuperview()
        }
        let validSplitterIDs = Set(store.sessions.map(\.id))
        let staleSplitterIDs = splitterViews.keys.filter { !validSplitterIDs.contains($0) }
        for sessionID in staleSplitterIDs {
            splitterViews.removeValue(forKey: sessionID)?.removeFromSuperview()
        }
    }

    private func buildMissingViews() {
        for session in store.sessions {
            if columnViews[session.id] == nil {
                let sessionID = session.id
                let column = TerminalColumnView(
                    session: session,
                    onSelect: { [weak self] in
                        self?.selectColumnFromPointer(sessionID)
                    },
                    onNewTerminal: { [weak self] in
                        self?.store.addColumn()
                    },
                    onCloseTerminal: { [weak self] in
                        guard let self else { return }
                        _ = store.closeSelectedColumn(confirm: false)
                        synchronize()
                    },
                    onOpenSettings: onOpenSettings,
                    onCycleTerminal: { [weak self] offset in
                        self?.selectColumn(at: (self?.currentIndex ?? 0) + offset)
                    },
                    shortcutSettings: shortcutSettings
                )
                columnViews[session.id] = column
                documentView.addSubview(column)
            }

            if splitterViews[session.id] == nil {
                let splitter = TerminalSplitterView(frame: .zero)
                splitter.onResize = { [weak self, weak session] delta in
                    guard let self, let session else { return }
                    session.updateColumnWidth(session.columnWidth + delta)
                    self.layoutDocument()
                }
                splitter.onResizeEnd = { [weak self] in
                    self?.store.save()
                }
                splitterViews[session.id] = splitter
                documentView.addSubview(splitter)
            }
        }
    }

    private func layoutDocument() {
        let height = max(scrollView.contentView.bounds.height, 1)
        var x: CGFloat = 0

        for session in store.sessions {
            columnViews[session.id]?.frame = NSRect(
                x: x,
                y: 0,
                width: session.columnWidth,
                height: height
            )
            x += session.columnWidth

            splitterViews[session.id]?.frame = NSRect(
                x: x - (Self.splitterHitWidth - Self.splitterLayoutWidth) / 2,
                y: 0,
                width: Self.splitterHitWidth,
                height: height
            )
            x += Self.splitterLayoutWidth
        }

        let addTerminalWidth = max(
            Self.minimumAddTerminalWidth,
            scrollView.contentView.bounds.width - x
        )
        addTerminalView.frame = NSRect(
            x: x,
            y: 0,
            width: addTerminalWidth,
            height: height
        )
        x += addTerminalWidth

        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(x, scrollView.contentView.bounds.width),
            height: height
        )
        for splitter in splitterViews.values {
            documentView.addSubview(splitter, positioned: .above, relativeTo: nil)
        }
        updateSurfaceVisibility()
    }

    private func selectColumn(at index: Int) {
        guard !store.sessions.isEmpty else { return }
        let wrappedIndex = (index % store.sessions.count + store.sessions.count) % store.sessions.count
        let sessionID = store.sessions[wrappedIndex].id
        store.select(sessionID)
        synchronize()
    }

    private func selectColumnFromPointer(_ sessionID: TerminalSessionID) {
        // Pointer selection already happens inside the current viewport. Keep it
        // visible while still synchronizing the selected surface and focus.
        suppressSelectionScroll = true
        store.select(sessionID)
        synchronize()
    }

    private func scrollToSelectedColumn() {
        guard !store.sessions.isEmpty else { return }
        scrollToColumn(at: currentIndex)
    }

    private func focusSelectedSurface() {
        guard let selectedID = store.selectedSessionID,
              let terminalView = columnViews[selectedID]?.terminalSurface,
              let window = view.window,
              window.isKeyWindow else { return }

        window.makeFirstResponder(terminalView)
        DispatchQueue.main.async { [weak self, weak terminalView, weak window] in
            guard let self,
                  let terminalView,
                  let window,
                  window.isKeyWindow,
                  store.selectedSessionID == selectedID,
                  terminalView.window === window else { return }
            window.makeFirstResponder(terminalView)
        }
    }

    private func scrollToColumn(at index: Int) {
        guard index >= 0, index < store.sessions.count else { return }
        let sessionID = store.sessions[index].id
        guard let frame = columnViews[sessionID]?.frame else { return }
        let viewportWidth = scrollView.contentView.bounds.width
        let maximumX = max(documentView.bounds.width - viewportWidth, 0)
        let centeredX = frame.midX - viewportWidth / 2
        let destination = NSPoint(x: min(max(centeredX, 0), maximumX), y: 0)
        guard destination != scrollView.contentView.bounds.origin else {
            updateSurfaceVisibility()
            return
        }

        selectionUpdate?.cancel()
        scrollAnimationGeneration += 1
        let generation = scrollAnimationGeneration
        isProgrammaticScroll = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(destination)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, scrollAnimationGeneration == generation else { return }
                isProgrammaticScroll = false
                scrollView.reflectScrolledClipView(scrollView.contentView)
                updateSurfaceVisibility()
            }
        }
    }

    private func updateSurfaceVisibility() {
        let visibleRect = scrollView.documentVisibleRect
        for session in store.sessions {
            let frame = columnViews[session.id]?.frame ?? .zero
            let isSelected = session.id == store.selectedSessionID
            session.setOccluded(!isSelected && !frame.intersects(visibleRect))
        }
        splitterViews.values.forEach { $0.refreshHoverState() }
    }

    @objc private func boundsDidChange() {
        updateSurfaceVisibility()
        selectionUpdate?.cancel()
        guard !isProgrammaticScroll else { return }
        let update = DispatchWorkItem { [weak self] in
            self?.selectNearestVisibleColumn()
        }
        selectionUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: update)
    }

    private func selectNearestVisibleColumn() {
        guard !store.sessions.isEmpty else { return }
        let centerX = scrollView.documentVisibleRect.midX
        let nearest = store.sessions.enumerated().min { lhs, rhs in
            let lhsCenter = columnViews[lhs.element.id]?.frame.midX ?? 0
            let rhsCenter = columnViews[rhs.element.id]?.frame.midX ?? 0
            return abs(lhsCenter - centerX) < abs(rhsCenter - centerX)
        }
        guard let session = nearest?.element, session.id != store.selectedSessionID else { return }
        suppressSelectionScroll = true
        store.select(session.id)
        synchronize()
    }
}

@MainActor
private final class TerminalColumnView: NSView {
    private static let titleHeight: CGFloat = 28

    private let titleView: NSHostingView<TerminalTitleBarView>
    private weak var terminalView: NSView?

    var terminalSurface: NSView? { terminalView }

    init(
        session: TerminalSession,
        onSelect: @escaping () -> Void,
        onNewTerminal: @escaping () -> Void,
        onCloseTerminal: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onCycleTerminal: @escaping (Int) -> Void,
        shortcutSettings: KeyboardShortcutSettings
    ) {
        titleView = NSHostingView(
            rootView: TerminalTitleBarView(
                session: session,
                onSelect: onSelect
            )
        )
        terminalView = session.view
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(titleView)
        addSubview(session.view)
        if let terminalView = session.view as? TerminalSurfaceView {
            terminalView.onSelect = onSelect
            terminalView.onNewTerminal = onNewTerminal
            terminalView.onCloseTerminal = onCloseTerminal
            terminalView.onOpenSettings = onOpenSettings
            terminalView.onCycleTerminal = onCycleTerminal
            terminalView.shortcutSettings = shortcutSettings
        }
    }

    required init?(coder: NSCoder) {
        fatalError("TerminalColumnView does not support NSCoder construction")
    }

    override func layout() {
        super.layout()
        titleView.frame = NSRect(
            x: 0,
            y: max(bounds.height - Self.titleHeight, 0),
            width: bounds.width,
            height: min(Self.titleHeight, bounds.height)
        )
        terminalView?.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(bounds.height - Self.titleHeight, 0)
        )
    }
}

@MainActor
private final class TerminalSplitterView: NSView {
    var onResize: ((CGFloat) -> Void)?
    var onResizeEnd: (() -> Void)?
    private let lineLayer = CALayer()
    private var previousX: CGFloat?
    private var hovered = false {
        didSet { updateLineColor() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackgroundColor()
        layer?.addSublayer(lineLayer)
        updateLineColor()
    }

    required init?(coder: NSCoder) {
        fatalError("TerminalSplitterView does not support NSCoder construction")
    }

    override func layout() {
        super.layout()
        lineLayer.frame = CGRect(x: floor(bounds.midX), y: 0, width: 1, height: bounds.height)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                owner: self
            )
        )
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
        updateLineColor()
    }

    override func mouseDown(with event: NSEvent) {
        previousX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previousX else { return }
        let currentX = event.locationInWindow.x
        self.previousX = currentX
        onResize?(currentX - previousX)
    }

    override func mouseUp(with _: NSEvent) {
        previousX = nil
        onResizeEnd?()
    }

    override func mouseEntered(with _: NSEvent) {
        hovered = true
    }

    override func mouseExited(with _: NSEvent) {
        hovered = false
    }

    func refreshHoverState() {
        guard let window, window.isKeyWindow else {
            hovered = false
            return
        }
        let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        hovered = bounds.contains(pointer)
    }

    private func updateLineColor() {
        lineLayer.backgroundColor = ColermTheme.resolved(
            hovered
                ? NSColor.labelColor.withAlphaComponent(0.72)
                : NSColor.separatorColor,
            for: effectiveAppearance
        ).cgColor
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = ColermTheme.resolved(
            ColermTheme.terminalTitleNS,
            for: effectiveAppearance
        ).cgColor
    }
}

@MainActor
private final class AddTerminalView: NSView {
    var onCreate: (() -> Void)?
    private let plusLayer = CAShapeLayer()
    private var hovered = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        plusLayer.fillColor = nil
        plusLayer.lineWidth = 1.5
        plusLayer.lineCap = .round
        layer?.addSublayer(plusLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("New Terminal")
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("AddTerminalView does not support NSCoder construction")
    }

    override func layout() {
        super.layout()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.midX - 12, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.midX + 12, y: bounds.midY))
        path.move(to: CGPoint(x: bounds.midX, y: bounds.midY - 12))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.midY + 12))
        plusLayer.frame = bounds
        plusLayer.path = path
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                owner: self
            )
        )
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func mouseEntered(with _: NSEvent) {
        hovered = true
    }

    override func mouseExited(with _: NSEvent) {
        hovered = false
    }

    override func mouseDown(with _: NSEvent) {
        onCreate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onCreate?()
        return true
    }

    private func updateAppearance() {
        let base = hovered ? NSColor.labelColor.withAlphaComponent(0.09) : ColermTheme.chromeNS
        layer?.backgroundColor = ColermTheme.resolved(base, for: effectiveAppearance).cgColor
        let plusColor = hovered ? NSColor.labelColor : NSColor.secondaryLabelColor
        plusLayer.strokeColor = ColermTheme.resolved(
            plusColor,
            for: effectiveAppearance
        ).cgColor
    }
}
