import Combine
import Foundation

enum WorkspaceLayoutMetrics {
    static let tabHeight: CGFloat = 36
    static let defaultVerticalTabsWidth: CGFloat = 220
    static let minimumVerticalTabsWidth: CGFloat = 160
    static let maximumVerticalTabsWidth: CGFloat = 360
    static let sidebarResizeHitWidth: CGFloat = 8
    static let sidebarResizeLineWidth: CGFloat = 1
}

@MainActor
final class WorkspaceLayoutSettings: ObservableObject {
    @Published private(set) var isVerticalTabsEnabled: Bool
    @Published private(set) var verticalTabsWidth: CGFloat

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVerticalTabsEnabled = defaults.bool(forKey: Self.verticalTabsKey)
        let storedWidth = defaults.double(forKey: Self.verticalTabsWidthKey)
        verticalTabsWidth = storedWidth > 0
            ? Self.boundedWidth(CGFloat(storedWidth))
            : WorkspaceLayoutMetrics.defaultVerticalTabsWidth
    }

    func setVerticalTabsEnabled(_ enabled: Bool) {
        guard isVerticalTabsEnabled != enabled else { return }
        isVerticalTabsEnabled = enabled
        defaults.set(enabled, forKey: Self.verticalTabsKey)
    }

    func setVerticalTabsWidth(_ width: CGFloat) {
        guard width.isFinite else { return }
        let boundedWidth = Self.boundedWidth(width)
        guard verticalTabsWidth != boundedWidth else { return }
        verticalTabsWidth = boundedWidth
        defaults.set(Double(boundedWidth), forKey: Self.verticalTabsWidthKey)
    }

    func reset() {
        setVerticalTabsEnabled(false)
        setVerticalTabsWidth(WorkspaceLayoutMetrics.defaultVerticalTabsWidth)
    }

    private static let verticalTabsKey = "workspaceLayout.verticalTabs"
    private static let verticalTabsWidthKey = "workspaceLayout.verticalTabsWidth"

    private static func boundedWidth(_ width: CGFloat) -> CGFloat {
        min(
            max(width, WorkspaceLayoutMetrics.minimumVerticalTabsWidth),
            WorkspaceLayoutMetrics.maximumVerticalTabsWidth
        )
    }
}
