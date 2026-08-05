import AppKit

@MainActor
final class PaletteTitlebarButton: NSButton {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        contentTintColor = .secondaryLabelColor
        layer?.backgroundColor = ColermTheme.resolved(
            NSColor.labelColor.withAlphaComponent(0.08),
            for: effectiveAppearance
        ).cgColor
    }
}
