import AppKit
import Combine
import SwiftUI

@MainActor
final class WorkspaceViewController: NSViewController {
    let store: WorkspaceStore

    private let pagerController: ColumnPagerController
    private let tabBarView: NSHostingView<WorkspaceTabBarView>
    private let footerView: NSHostingView<WorkspaceFooterView>
    private var storeCancellable: AnyCancellable?

    convenience init(
        shortcutSettings: KeyboardShortcutSettings,
        onOpenSettings: @escaping () -> Void
    ) {
        self.init(
            store: WorkspaceStore(),
            shortcutSettings: shortcutSettings,
            onOpenSettings: onOpenSettings
        )
    }

    init(
        store: WorkspaceStore,
        shortcutSettings: KeyboardShortcutSettings,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.pagerController = ColumnPagerController(
            store: store,
            shortcutSettings: shortcutSettings,
            onOpenSettings: onOpenSettings
        )
        self.tabBarView = NSHostingView(
            rootView: WorkspaceTabBarView(store: store)
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
        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 36),
            pagerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerController.view.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            pagerController.view.bottomAnchor.constraint(equalTo: footerView.topAnchor),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 37)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        storeCancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.pagerController.synchronize()
            }
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
        _ = store.closeSelectedColumn()
        pagerController.synchronize()
    }

    func closeWindowIfAllowed() -> Bool {
        store.requestWindowClose()
    }
}
