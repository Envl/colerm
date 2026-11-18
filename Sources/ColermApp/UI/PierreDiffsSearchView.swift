import AppKit
import WebKit

@MainActor
final class PierreDiffsSearchView: NSView, NSSearchFieldDelegate {
    let webView: PierreDiffsWebView

    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "No matches")
    private let findBar = NSStackView()
    private lazy var previousButton = makeButton(
        "chevron.up", label: "Previous Match", action: #selector(findPrevious(_:))
    )
    private lazy var nextButton = makeButton(
        "chevron.down", label: "Next Match", action: #selector(findNext(_:))
    )
    private var searchRequest = UUID()

    init(webView: PierreDiffsWebView) {
        self.webView = webView
        super.init(frame: .zero)

        searchField.controlSize = .small
        searchField.placeholderString = "Find in Diffs"
        searchField.setAccessibilityLabel("Find in Diffs")
        searchField.delegate = self
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.isHidden = true

        findBar.alignment = .centerY
        findBar.spacing = 4
        findBar.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        findBar.addArrangedSubview(searchField)
        findBar.addArrangedSubview(statusLabel)
        findBar.addArrangedSubview(previousButton)
        findBar.addArrangedSubview(nextButton)
        findBar.addArrangedSubview(makeButton("xmark", label: "Close Find", action: #selector(closeFind(_:))))
        findBar.isHidden = true

        let stack = NSStackView(views: [findBar, webView])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PierreDiffsSearchView does not support NSCoder construction")
    }

    func showFindBar() {
        if findBar.isHidden {
            findBar.isHidden = false
            refreshSearch()
        }
        layoutSubtreeIfNeeded()
        searchField.selectText(nil)
    }

    func hideFindBar(restoringFocusTo view: NSView? = nil) {
        guard !findBar.isHidden else { return }
        if searchField.currentEditor() != nil {
            window?.makeFirstResponder(view ?? webView)
        }
        findBar.isHidden = true
        search("")
    }

    func refreshSearch() {
        guard !findBar.isHidden else { return }
        search(searchField.stringValue)
    }

    func controlTextDidChange(_ notification: Notification) {
        let editor = searchField.currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
        refreshSearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            search(searchField.stringValue, backwards: backwards)
        case #selector(NSResponder.cancelOperation(_:)):
            hideFindBar()
        default:
            return false
        }
        return true
    }

    private func search(_ query: String, backwards: Bool = false) {
        let request = UUID()
        searchRequest = request
        if query.isEmpty {
            previousButton.isEnabled = false
            nextButton.isEnabled = false
            statusLabel.isHidden = true
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        webView.find(query, configuration: configuration) { [weak self] result in
            guard let self, self.searchRequest == request, !query.isEmpty else { return }
            self.previousButton.isEnabled = result.matchFound
            self.nextButton.isEnabled = result.matchFound
            self.statusLabel.isHidden = result.matchFound
        }
    }

    @objc private func findPrevious(_: Any?) {
        search(searchField.stringValue, backwards: true)
    }

    @objc private func findNext(_: Any?) {
        refreshSearch()
    }

    @objc private func closeFind(_: Any?) {
        hideFindBar()
    }

    private func makeButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }
}
