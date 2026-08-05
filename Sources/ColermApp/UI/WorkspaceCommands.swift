import AppKit

@MainActor
final class WorkspaceCommandRouter: NSObject {
    weak var workspace: WorkspaceViewController?
    var onSearchTerminals: (() -> Void)?

    @objc func newColumn(_: Any?) {
        workspace?.store.addColumn()
    }

    @objc func closeColumn(_: Any?) {
        workspace?.closeSelectedColumn()
    }

    @objc func previousColumn(_: Any?) {
        workspace?.selectPreviousColumn()
    }

    @objc func nextColumn(_: Any?) {
        workspace?.selectNextColumn()
    }

    @objc func searchTerminals(_: Any?) {
        onSearchTerminals?()
    }

    @objc func selectColumn(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? Int else { return }
        workspace?.selectColumn(number: number)
    }
}
