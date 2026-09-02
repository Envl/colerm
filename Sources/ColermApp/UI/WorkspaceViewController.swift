import AppKit
import Combine
import SwiftUI

@MainActor
final class WorkspaceViewController: NSViewController {
    let store: WorkspaceStore

    private let workspaceLayoutSettings: WorkspaceLayoutSettings
    private let pagerController: ColumnPagerController
    private let sidebarResizeHandle = WorkspaceSidebarResizeHandle(frame: .zero)
    private lazy var tabBarView: NSHostingView<WorkspaceTabBarView> = {
        NSHostingView(
            rootView: WorkspaceTabBarView(
                store: store,
                layoutSettings: workspaceLayoutSettings,
                onSelectSession: { [weak self] sessionID in
                    self?.selectColumn(sessionID)
                }
            )
        )
    }()
    private let footerView: NSHostingView<WorkspaceFooterView>
    private var storeCancellable: AnyCancellable?
    private var layoutSettingsCancellable: AnyCancellable?
    private var verticalTabsWidthCancellable: AnyCancellable?
    private var horizontalTabBarConstraints: [NSLayoutConstraint] = []
    private var verticalTabBarConstraints: [NSLayoutConstraint] = []
    private var horizontalPagerConstraints: [NSLayoutConstraint] = []
    private var verticalPagerConstraints: [NSLayoutConstraint] = []
    private var verticalTabBarWidthConstraint: NSLayoutConstraint?

    convenience init(
        shortcutSettings: KeyboardShortcutSettings,
        workspaceLayoutSettings: WorkspaceLayoutSettings,
        onOpenSettings: @escaping () -> Void
    ) {
        self.init(
            store: WorkspaceStore(),
            shortcutSettings: shortcutSettings,
            workspaceLayoutSettings: workspaceLayoutSettings,
            onOpenSettings: onOpenSettings
        )
    }

    init(
        store: WorkspaceStore,
        shortcutSettings: KeyboardShortcutSettings,
        workspaceLayoutSettings: WorkspaceLayoutSettings,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.workspaceLayoutSettings = workspaceLayoutSettings
        self.pagerController = ColumnPagerController(
            store: store,
            shortcutSettings: shortcutSettings,
            onOpenSettings: onOpenSettings
        )
        self.footerView = NSHostingView(
            rootView: WorkspaceFooterView(
                store: store,
                shortcutSettings: shortcutSettings
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("WorkspaceViewController does not support NSCoder construction")
    }

    override func loadView() {
        view = ThemedBackgroundView(color: ColermTheme.workspaceBackgroundNS)

        addChild(pagerController)
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        pagerController.view.translatesAutoresizingMaskIntoConstraints = false
        footerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBarView)
        view.addSubview(pagerController.view)
        view.addSubview(footerView)
        view.addSubview(sidebarResizeHandle)
        sidebarResizeHandle.onResize = { [weak self] delta in
            guard let self else { return }
            workspaceLayoutSettings.setVerticalTabsWidth(
                workspaceLayoutSettings.verticalTabsWidth + delta
            )
        }
        sidebarResizeHandle.isHidden = !workspaceLayoutSettings.isVerticalTabsEnabled
        horizontalTabBarConstraints = [
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 36)
        ]
        let verticalTabBarWidthConstraint = tabBarView.widthAnchor.constraint(
            equalToConstant: workspaceLayoutSettings.verticalTabsWidth
        )
        self.verticalTabBarWidthConstraint = verticalTabBarWidthConstraint
        verticalTabBarConstraints = [
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.bottomAnchor.constraint(equalTo: footerView.topAnchor),
            verticalTabBarWidthConstraint
        ]
        horizontalPagerConstraints = [
            pagerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerController.view.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            pagerController.view.bottomAnchor.constraint(equalTo: footerView.topAnchor)
        ]
        verticalPagerConstraints = [
            pagerController.view.leadingAnchor.constraint(equalTo: tabBarView.trailingAnchor),
            pagerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pagerController.view.bottomAnchor.constraint(equalTo: footerView.topAnchor)
        ]
        NSLayoutConstraint.activate([
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 37)
        ])
        applySidebarWidth(workspaceLayoutSettings.verticalTabsWidth)
        applyTabLayout(isVertical: workspaceLayoutSettings.isVerticalTabsEnabled)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSidebarResizeHandle()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        storeCancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.pagerController.synchronize()
            }
        }
        layoutSettingsCancellable = workspaceLayoutSettings.$isVerticalTabsEnabled.sink { [weak self] isVertical in
            self?.applyTabLayout(isVertical: isVertical)
        }
        verticalTabsWidthCancellable = workspaceLayoutSettings.$verticalTabsWidth.sink { [weak self] width in
            self?.applySidebarWidth(width)
        }
        pagerController.synchronize()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        pagerController.synchronize()
        view.window?.makeFirstResponder(store.selectedSession?.view)
    }

    func selectPreviousColumn() {
        pagerController.previousColumn()
    }

    func selectNextColumn() {
        pagerController.nextColumn()
    }

    func selectColumn(_ sessionID: TerminalSessionID) {
        store.select(sessionID)
        pagerController.synchronize()
        restoreTerminalFocus()
    }

    func selectColumn(number: Int) {
        guard number > 0, number <= store.sessions.count else { return }
        selectColumn(store.sessions[number - 1].id)
    }

    func restoreTerminalFocus() {
        guard let window = view.window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(store.selectedSession?.view)
    }

    func closeSelectedColumn() {
        _ = store.closeSelectedColumn(confirm: false)
        pagerController.synchronize()
    }

    func closeWindowIfAllowed() -> Bool {
        store.requestWindowClose()
    }

    private func applyTabLayout(isVertical: Bool) {
        sidebarResizeHandle.isHidden = !isVertical
        NSLayoutConstraint.deactivate(isVertical ? horizontalTabBarConstraints : verticalTabBarConstraints)
        NSLayoutConstraint.deactivate(isVertical ? horizontalPagerConstraints : verticalPagerConstraints)
        NSLayoutConstraint.activate(isVertical ? verticalTabBarConstraints : horizontalTabBarConstraints)
        NSLayoutConstraint.activate(isVertical ? verticalPagerConstraints : horizontalPagerConstraints)
        view.needsLayout = true
    }

    private func applySidebarWidth(_ width: CGFloat) {
        verticalTabBarWidthConstraint?.constant = width
        view.needsLayout = true
    }

    private func layoutSidebarResizeHandle() {
        guard workspaceLayoutSettings.isVerticalTabsEnabled else {
            sidebarResizeHandle.frame = .zero
            return
        }

        let workspaceBottom = footerView.frame.maxY
        sidebarResizeHandle.frame = NSRect(
            x: tabBarView.frame.maxX - WorkspaceLayoutMetrics.sidebarResizeHitWidth / 2,
            y: workspaceBottom,
            width: WorkspaceLayoutMetrics.sidebarResizeHitWidth,
            height: max(view.bounds.maxY - workspaceBottom, 0)
        )
    }
}

@MainActor
private final class WorkspaceSidebarResizeHandle: NSView {
    var onResize: ((CGFloat) -> Void)?

    private let lineLayer = CALayer()
    private var previousX: CGFloat?
    private var hovered = false {
        didSet { updateLineColor() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(lineLayer)
        updateLineColor()
    }

    required init?(coder: NSCoder) {
        fatalError("WorkspaceSidebarResizeHandle does not support NSCoder construction")
    }

    override func layout() {
        super.layout()
        lineLayer.frame = CGRect(
            x: floor(bounds.midX),
            y: 0,
            width: WorkspaceLayoutMetrics.sidebarResizeLineWidth,
            height: bounds.height
        )
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
    }

    override func mouseEntered(with _: NSEvent) {
        hovered = true
    }

    override func mouseExited(with _: NSEvent) {
        hovered = false
    }

    private func updateLineColor() {
        lineLayer.backgroundColor = ColermTheme.resolved(
            hovered
                ? NSColor.labelColor.withAlphaComponent(0.72)
                : ColermTheme.terminalSplitterNS,
            for: effectiveAppearance
        ).cgColor
    }
}
