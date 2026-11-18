import AppKit
import SwiftUI
import WebKit

enum PierreDiffLayoutStyle: String {
    case unified
    case split

    static let defaultsKey = "terminalDiffSidebar.diffStyle"

    static func persisted(in defaults: UserDefaults = .standard) -> PierreDiffLayoutStyle {
        guard let raw = defaults.string(forKey: defaultsKey),
              let style = PierreDiffLayoutStyle(rawValue: raw)
        else {
            return .unified
        }
        return style
    }

    func persist(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    var toggled: PierreDiffLayoutStyle {
        self == .unified ? .split : .unified
    }
}

enum PierreDiffsAssets {
    static var indexHTMLURL: URL? {
        if let resourceRoot = Bundle.main.resourceURL {
            let bundled = resourceRoot
                .appendingPathComponent("diffs", isDirectory: true)
                .appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        let sourceTreeCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // UI
            .deletingLastPathComponent() // ColermApp
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Resources/diffs/index.html")
        if FileManager.default.fileExists(atPath: sourceTreeCandidate.path) {
            return sourceTreeCandidate
        }

        return nil
    }
}

@MainActor
final class PierreDiffsWebView: WKWebView {
    var onSelectColumn: (() -> Void)?
    var forwardsHorizontalScrollToPager = true

    static func sanitizeContextMenu(_ menu: NSMenu) {
        let allowedIdentifiers: Set<String> = ["WKMenuItemIdentifierCopy"]
        let keptItems = menu.items.filter { item in
            guard !item.isSeparatorItem,
                  let identifier = item.identifier?.rawValue
            else {
                return false
            }
            return allowedIdentifiers.contains(identifier)
        }
        menu.removeAllItems()
        for item in keptItems {
            menu.addItem(item)
        }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        Self.sanitizeContextMenu(menu)
        super.willOpenMenu(menu, with: event)
    }

    override func reload() -> WKNavigation? {
        nil
    }

    override func reload(_ sender: Any?) {}

    override func reloadFromOrigin() -> WKNavigation? {
        nil
    }

    override func reloadFromOrigin(_ sender: Any?) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command
        ])
        if (modifiers == [.command] || modifiers == [.command, .shift]),
           event.charactersIgnoringModifiers?.lowercased() == "r"
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onSelectColumn?()
        super.mouseDown(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncAppearance()
    }

    override func scrollWheel(with event: NSEvent) {
        let isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.25
        if forwardsHorizontalScrollToPager, isHorizontal, let enclosingScrollView {
            enclosingScrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    func currentThemeType() -> String {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
    }

    func syncAppearance() {
        let theme = currentThemeType()
        evaluateJavaScript("window.ColermDiffViewer?.setAppearance('\(theme)');", completionHandler: nil)
    }
}

struct TerminalDiffSidebarView: View {
    @ObservedObject var session: TerminalSession
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onLoadFileDetail: (String, String) async -> GitLoadedFileDetail?
    let onCreateSearchView: (PierreDiffsSearchView) -> Void

    @AppStorage(PierreDiffLayoutStyle.defaultsKey) private var diffStyle: PierreDiffLayoutStyle = .unified
    @State private var allCollapsed = false
    @State private var hasHorizontalScroll = false
    @State private var collapseCommandID = UUID()
    @State private var resetDetailsCommandID = UUID()
    @State private var requestedCollapsedState: Bool?
    @State private var isSplitHovered = false
    @State private var isCollapseAllHovered = false
    @State private var isRefreshHovered = false
    @State private var isCloseHovered = false

    private static let headerHeight: CGFloat = 28

    private var diffSummaryCounts: (files: Int, insertions: Int, deletions: Int)? {
        if let snapshot = session.diffSnapshot {
            guard !snapshot.files.isEmpty else { return nil }
            return (snapshot.files.count, snapshot.totalInsertions, snapshot.totalDeletions)
        }
        if let git = session.metadata.git, git.changedFiles > 0 {
            return (git.changedFiles, git.insertions, git.deletions)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            PierreDiffsWebViewRepresentable(
                snapshot: session.diffSnapshot,
                isLoading: session.isLoadingDiff,
                diffStyle: diffStyle,
                hasHorizontalScroll: hasHorizontalScroll,
                collapseCommandID: collapseCommandID,
                resetDetailsCommandID: resetDetailsCommandID,
                requestedCollapsedState: requestedCollapsedState,
                onSelectColumn: onSelect,
                onLoadFileDetail: onLoadFileDetail,
                onCreateSearchView: onCreateSearchView,
                onUpdateCollapseState: { collapsed, horizontalScroll in
                    allCollapsed = collapsed
                    hasHorizontalScroll = horizontalScroll
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColermTheme.workspaceBackground)
    }

    private var headerBar: some View {
        HStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("Diffs")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColermTheme.terminalTitleText)

                if let counts = diffSummaryCounts {
                    HStack(spacing: 5) {
                        Text("\(counts.files)")
                            .foregroundStyle(ColermTheme.secondaryText)

                        if counts.insertions > 0 {
                            Text("+\(counts.insertions)")
                                .foregroundStyle(.green)
                        }
                        if counts.deletions > 0 {
                            Text("−\(counts.deletions)")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                }

                Spacer(minLength: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            if let files = session.diffSnapshot?.files, !files.isEmpty {
                Button {
                    onSelect()
                    diffStyle = diffStyle.toggled
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(
                            diffStyle == .split
                                ? Color.primary.opacity(isSplitHovered ? 0.17 : 0.12)
                                : (isSplitHovered ? Color.primary.opacity(0.08) : Color.clear),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColermTheme.terminalTitleText)
                .onHover { isSplitHovered = $0 }
                .help(diffStyle == .split ? "Switch to Unified Diff" : "Switch to Split Diff")
                .accessibilityLabel(diffStyle == .split ? "Switch to Unified Diff" : "Switch to Split Diff")
            }

            if let files = session.diffSnapshot?.files, files.count > 1 {
                Button {
                    onSelect()
                    let next = !allCollapsed
                    allCollapsed = next
                    requestedCollapsedState = next
                    collapseCommandID = UUID()
                } label: {
                    Image(systemName: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(
                            isCollapseAllHovered ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColermTheme.terminalTitleText)
                .onHover { isCollapseAllHovered = $0 }
                .help(allCollapsed ? "Expand All Files" : "Collapse All Files")
            }

            Button {
                onSelect()
                resetDetailsCommandID = UUID()
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 20)
                    .background(
                        isRefreshHovered ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColermTheme.terminalTitleText)
            .onHover { isRefreshHovered = $0 }
            .help("Refresh Diffs")
            .accessibilityLabel("Refresh Diffs")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 20)
                    .background(
                        isCloseHovered ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColermTheme.terminalTitleText)
            .onHover { isCloseHovered = $0 }
            .help("Hide Diffs")
            .accessibilityLabel("Hide Diffs")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: Self.headerHeight)
        .background(ColermTheme.terminalTitle)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct PierreDiffsPayload: Encodable {
    struct NonTextFilePayload: Encodable {
        let path: String
        let oldPath: String?
        let kind: String
        let note: String
        let canLoadDetail: Bool
    }

    let isLoading: Bool
    let hasSnapshot: Bool
    let rawPatch: String
    let untrackedFiles: [GitUntrackedDiffFile]
    let nonTextFiles: [NonTextFilePayload]
}

private struct PierreDiffsWebViewRepresentable: NSViewRepresentable {
    static let messageHandlerName = "colermDiffs"

    let snapshot: GitDiffSnapshot?
    let isLoading: Bool
    let diffStyle: PierreDiffLayoutStyle
    let hasHorizontalScroll: Bool
    let collapseCommandID: UUID
    let resetDetailsCommandID: UUID
    let requestedCollapsedState: Bool?
    let onSelectColumn: () -> Void
    let onLoadFileDetail: (String, String) async -> GitLoadedFileDetail?
    let onCreateSearchView: (PierreDiffsSearchView) -> Void
    let onUpdateCollapseState: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            resetDetailsCommandID: resetDetailsCommandID,
            onSelectColumn: onSelectColumn,
            onLoadFileDetail: onLoadFileDetail,
            onUpdateCollapseState: onUpdateCollapseState
        )
    }

    func makeNSView(context: Context) -> PierreDiffsSearchView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: Self.messageHandlerName
        )

        let webView = PierreDiffsWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        webView.onSelectColumn = onSelectColumn
        webView.forwardsHorizontalScrollToPager = (diffStyle == .unified && !hasHorizontalScroll)
        webView.setValue(false, forKey: "drawsBackground")

        let searchView = PierreDiffsSearchView(webView: webView)
        context.coordinator.searchView = searchView
        onCreateSearchView(searchView)
        context.coordinator.loadInitialPage()
        context.coordinator.update(
            snapshot: snapshot,
            isLoading: isLoading,
            diffStyle: diffStyle,
            collapseCommandID: collapseCommandID,
            resetDetailsCommandID: resetDetailsCommandID,
            requestedCollapsedState: requestedCollapsedState
        )
        return searchView
    }

    func updateNSView(_ searchView: PierreDiffsSearchView, context: Context) {
        let webView = searchView.webView
        webView.onSelectColumn = onSelectColumn
        webView.forwardsHorizontalScrollToPager = (diffStyle == .unified && !hasHorizontalScroll)
        context.coordinator.onSelectColumn = onSelectColumn
        context.coordinator.onLoadFileDetail = onLoadFileDetail
        context.coordinator.onUpdateCollapseState = onUpdateCollapseState
        context.coordinator.update(
            snapshot: snapshot,
            isLoading: isLoading,
            diffStyle: diffStyle,
            collapseCommandID: collapseCommandID,
            resetDetailsCommandID: resetDetailsCommandID,
            requestedCollapsedState: requestedCollapsedState
        )
    }

    static func dismantleNSView(_ searchView: PierreDiffsSearchView, coordinator: Coordinator) {
        let webView = searchView.webView
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.messageHandlerName
        )
        webView.navigationDelegate = nil
        coordinator.searchView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var searchView: PierreDiffsSearchView?
        private var webView: PierreDiffsWebView? { searchView?.webView }
        var onSelectColumn: () -> Void
        var onLoadFileDetail: (String, String) async -> GitLoadedFileDetail?
        var onUpdateCollapseState: (Bool, Bool) -> Void

        private var allowedPageURL: URL?
        private var isViewerReady = false
        private var lastRenderedSignature: PayloadSignature?
        private var lastSnapshotRoot: URL?
        private var lastAppliedDiffStyle: PierreDiffLayoutStyle = .unified
        private var lastCollapseCommandID: UUID?
        private var lastResetDetailsCommandID: UUID
        private var pendingResetDetails = false
        private var pendingSnapshot: GitDiffSnapshot?
        private var pendingIsLoading = false
        private var pendingDiffStyle: PierreDiffLayoutStyle = .unified
        private var pendingCollapsedState: Bool?

        private struct PayloadSignature: Equatable {
            let snapshot: GitDiffSnapshot?
            let isLoading: Bool
        }

        init(
            resetDetailsCommandID: UUID,
            onSelectColumn: @escaping () -> Void,
            onLoadFileDetail: @escaping (String, String) async -> GitLoadedFileDetail?,
            onUpdateCollapseState: @escaping (Bool, Bool) -> Void
        ) {
            self.lastResetDetailsCommandID = resetDetailsCommandID
            self.onSelectColumn = onSelectColumn
            self.onLoadFileDetail = onLoadFileDetail
            self.onUpdateCollapseState = onUpdateCollapseState
        }

        func loadInitialPage() {
            guard let webView, let indexURL = PierreDiffsAssets.indexHTMLURL else { return }
            allowedPageURL = indexURL.standardizedFileURL
            webView.loadFileURL(
                indexURL,
                allowingReadAccessTo: indexURL.deletingLastPathComponent()
            )
        }

        func update(
            snapshot: GitDiffSnapshot?,
            isLoading: Bool,
            diffStyle: PierreDiffLayoutStyle,
            collapseCommandID: UUID,
            resetDetailsCommandID: UUID,
            requestedCollapsedState: Bool?
        ) {
            if let root = snapshot?.root, root != lastSnapshotRoot {
                if lastSnapshotRoot != nil {
                    pendingResetDetails = true
                }
                lastSnapshotRoot = root
            }

            if lastResetDetailsCommandID != resetDetailsCommandID {
                lastResetDetailsCommandID = resetDetailsCommandID
                pendingResetDetails = true
                lastRenderedSignature = nil
            }

            pendingSnapshot = snapshot
            pendingIsLoading = isLoading
            pendingDiffStyle = diffStyle

            if lastCollapseCommandID != collapseCommandID {
                lastCollapseCommandID = collapseCommandID
                pendingCollapsedState = requestedCollapsedState
            }

            flushIfReady()
        }

        func userContentController(
            _: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else {
                return
            }

            switch type {
            case "ready":
                isViewerReady = true
                lastAppliedDiffStyle = .unified
                webView?.syncAppearance()
                flushIfReady()
            case "selectColumn":
                onSelectColumn()
            case "collapseState":
                let allCollapsed = body["allCollapsed"] as? Bool ?? false
                let horizontalScroll = body["hasHorizontalScroll"] as? Bool ?? false
                onUpdateCollapseState(allCollapsed, horizontalScroll)
                searchView?.refreshSearch()
            case "loadFileDetail":
                guard let path = body["path"] as? String, !path.isEmpty else { return }
                let kind = body["kind"] as? String ?? "U"
                onSelectColumn()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let detail = await self.onLoadFileDetail(path, kind)
                        ?? GitLoadedFileDetail(
                            path: path,
                            kind: kind,
                            textContents: nil,
                            imageDataURL: nil,
                            truncatedNote: nil,
                            errorNote: "Unable to read file"
                        )
                    guard let data = try? JSONEncoder().encode(detail) else { return }
                    let detailJSON = String(decoding: data, as: UTF8.self)
                    _ = try? await self.webView?.evaluateJavaScript(
                        "window.ColermDiffViewer?.resolveFileDetail(\(detailJSON));"
                    )
                }
            default:
                break
            }
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .reload
                || navigationAction.navigationType == .backForward
                || navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }

            if let targetURL = navigationAction.request.url?.standardizedFileURL,
               let allowedPageURL,
               targetURL == allowedPageURL {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
        }

        private func flushIfReady() {
            guard isViewerReady, let webView else { return }

            webView.syncAppearance()

            if pendingResetDetails {
                pendingResetDetails = false
                webView.evaluateJavaScript(
                    "window.ColermDiffViewer?.clearLoadedDetails();",
                    completionHandler: nil
                )
            }

            if lastAppliedDiffStyle != pendingDiffStyle {
                lastAppliedDiffStyle = pendingDiffStyle
                webView.evaluateJavaScript(
                    "window.ColermDiffViewer?.setDiffStyle('\(pendingDiffStyle.rawValue)');",
                    completionHandler: nil
                )
            }

            let nextSignature = PayloadSignature(
                snapshot: pendingSnapshot,
                isLoading: pendingIsLoading
            )
            if lastRenderedSignature != nextSignature {
                lastRenderedSignature = nextSignature
                if let payloadJSON = encodePayloadJSON(
                    snapshot: pendingSnapshot,
                    isLoading: pendingIsLoading
                ) {
                    webView.evaluateJavaScript(
                        "window.ColermDiffViewer?.renderSnapshot(\(payloadJSON));",
                        completionHandler: nil
                    )
                }
            }

            if let collapsed = pendingCollapsedState {
                pendingCollapsedState = nil
                webView.evaluateJavaScript(
                    "window.ColermDiffViewer?.setAllCollapsed(\(collapsed ? "true" : "false"));",
                    completionHandler: nil
                )
            }
        }

        private func encodePayloadJSON(
            snapshot: GitDiffSnapshot?,
            isLoading: Bool
        ) -> String? {
            let nonTextFiles: [PierreDiffsPayload.NonTextFilePayload] = (snapshot?.files ?? [])
                .filter { $0.kind != .untracked && $0.hunks.isEmpty }
                .map { file in
                    let canLoadDetail: Bool
                    if file.isBinary {
                        canLoadDetail = file.kind != .deleted
                            && GitDiffParser.imageMIMEType(forPath: file.path) != nil
                    } else {
                        canLoadDetail = file.kind != .added && file.kind != .deleted
                    }
                    return PierreDiffsPayload.NonTextFilePayload(
                        path: file.path,
                        oldPath: file.oldPath,
                        kind: file.kind.rawValue,
                        note: file.summaryNote ?? "Binary or metadata change",
                        canLoadDetail: canLoadDetail
                    )
                }

            let payload = PierreDiffsPayload(
                isLoading: isLoading,
                hasSnapshot: snapshot != nil,
                rawPatch: snapshot?.rawPatch ?? "",
                untrackedFiles: snapshot?.untrackedFiles ?? [],
                nonTextFiles: nonTextFiles
            )
            guard let data = try? JSONEncoder().encode(payload) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any WKScriptMessageHandler)?

    init(delegate: any WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
