import AppKit

@MainActor
class TitlebarPillButton: NSButton {
    private var pointerInside = false
    private var hoverTrackingArea: NSTrackingArea?

    var normalTintColor: NSColor { .secondaryLabelColor }
    var normalBackgroundColor: NSColor { NSColor.labelColor.withAlphaComponent(0.08) }
    var hoverBackgroundColor: NSColor { NSColor.labelColor.withAlphaComponent(0.16) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let hoverTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(hoverTrackingArea)
        self.hoverTrackingArea = hoverTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        updateAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        updateAppearance()
        super.mouseExited(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        contentTintColor = ColermTheme.resolved(normalTintColor, for: effectiveAppearance)
        let background = pointerInside ? hoverBackgroundColor : normalBackgroundColor
        layer?.backgroundColor = ColermTheme.resolved(background, for: effectiveAppearance).cgColor
    }
}
