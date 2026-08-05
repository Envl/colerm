import AppKit

@MainActor
final class ThemedBackgroundView: NSView {
    private let backgroundColor: NSColor

    init(color: NSColor) {
        backgroundColor = color
        super.init(frame: .zero)
        wantsLayer = true
        updateBackgroundColor()
    }

    required init?(coder: NSCoder) {
        fatalError("ThemedBackgroundView does not support NSCoder construction")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = ColermTheme.resolved(
            backgroundColor,
            for: effectiveAppearance
        ).cgColor
    }
}
