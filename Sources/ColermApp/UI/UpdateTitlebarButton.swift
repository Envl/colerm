import AppKit

@MainActor
final class UpdateTitlebarButton: TitlebarPillButton {
    override var normalTintColor: NSColor { .systemBlue }
    override var normalBackgroundColor: NSColor { NSColor.systemBlue.withAlphaComponent(0.18) }
    override var hoverBackgroundColor: NSColor { NSColor.systemBlue.withAlphaComponent(0.30) }
}
