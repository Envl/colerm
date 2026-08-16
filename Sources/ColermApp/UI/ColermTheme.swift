import AppKit
import SwiftUI

enum ColermTheme {
    static let workspaceBackgroundNS = dynamic(
        light: srgb(0.965),
        dark: srgb(0.055)
    )
    static let chromeNS = dynamic(
        light: srgb(0.935),
        dark: srgb(0.102)
    )
    static let terminalTitleNS = dynamic(
        light: srgb(0.955),
        dark: NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
    )
    static let terminalSplitterNS = dynamic(
        light: srgb(0.76),
        dark: srgb(0.30)
    )
    static let selectedTabNS = dynamic(
        light: .white,
        dark: srgb(0.125)
    )
    static let paletteCanvasNS = dynamic(
        light: srgb(0.975),
        dark: srgb(0.072)
    )
    static let paletteRaisedNS = dynamic(
        light: .white,
        dark: srgb(0.105)
    )
    static let paletteFooterNS = dynamic(
        light: srgb(0.945),
        dark: srgb(0.058)
    )
    static let palettePrimaryTextNS = dynamic(
        light: srgb(0.10),
        dark: srgb(0.90)
    )
    static let paletteSecondaryTextNS = dynamic(
        light: srgb(0.38),
        dark: srgb(0.58)
    )
    static let paletteAccentNS = dynamic(
        light: NSColor(srgbRed: 0.08, green: 0.48, blue: 0.46, alpha: 1),
        dark: NSColor(srgbRed: 0.43, green: 0.82, blue: 0.79, alpha: 1)
    )

    static var workspaceBackground: Color { Color(nsColor: workspaceBackgroundNS) }
    static var chrome: Color { Color(nsColor: chromeNS) }
    static var terminalTitle: Color { Color(nsColor: terminalTitleNS) }
    static var selectedTab: Color { Color(nsColor: selectedTabNS) }
    static var paletteCanvas: Color { Color(nsColor: paletteCanvasNS) }
    static var paletteRaised: Color { Color(nsColor: paletteRaisedNS) }
    static var paletteFooter: Color { Color(nsColor: paletteFooterNS) }
    static var palettePrimaryText: Color { Color(nsColor: palettePrimaryTextNS) }
    static var paletteSecondaryText: Color { Color(nsColor: paletteSecondaryTextNS) }
    static var paletteAccent: Color { Color(nsColor: paletteAccentNS) }
    static var primaryText: Color { Color(nsColor: .labelColor) }
    static var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }

    static let ghosttyTheme = "light:Colerm Light,dark:Colerm Dark"

    static func resolved(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func srgb(_ white: CGFloat) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: 1)
    }
}
