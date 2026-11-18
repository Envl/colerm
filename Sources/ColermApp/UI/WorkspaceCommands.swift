import AppKit

@MainActor
final class WorkspaceCommandRouter: NSObject, NSMenuItemValidation {
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

    @objc func findInDiffs(_: Any?) {
        workspace?.findInDiffs()
    }

    @objc func selectColumn(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? Int else { return }
        workspace?.selectColumn(number: number)
    }

    @objc func paste(_ sender: Any?) {
        if let terminalView = NSApp.keyWindow?.firstResponder as? TerminalSurfaceView {
            terminalView.pasteIntoTerminal(sender)
            return
        }
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(findInDiffs(_:)) {
            return workspace?.canFindInDiffs == true
        }
        if menuItem.action == #selector(paste(_:)) {
            if NSApp.keyWindow?.firstResponder is TerminalSurfaceView {
                return TerminalPasteboard.canRead(from: .general)
            }
            return NSApp.target(forAction: #selector(NSText.paste(_:))) != nil
        }
        return true
    }
}
