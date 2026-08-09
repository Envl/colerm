import AppKit

@MainActor
final class PaletteTitlebarButton: TitlebarPillButton {
    override var normalTintColor: NSColor { .labelColor }
}
