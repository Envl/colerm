import AppKit
import SwiftUI

enum TerminalAccent: Int, CaseIterable {
    case teal
    case purple
    case amber
    case pink
    case blue
    case green
    case neutral

    var color: Color {
        switch self {
        case .teal:
            Color(nsColor: .systemTeal)
        case .purple:
            Color(nsColor: .systemPurple)
        case .amber:
            Color(nsColor: .systemOrange)
        case .pink:
            Color(nsColor: .systemPink)
        case .blue:
            Color(nsColor: .systemBlue)
        case .green:
            Color(nsColor: .systemGreen)
        case .neutral:
            Color(nsColor: .labelColor)
        }
    }

    var contrastingText: Color {
        switch self {
        case .neutral:
            Color(nsColor: .windowBackgroundColor)
        default:
            Color.black.opacity(0.76)
        }
    }

    static func forSession(_ id: TerminalSessionID) -> TerminalAccent {
        var uuid = id.uuid
        let index = withUnsafeBytes(of: &uuid) { bytes in
            bytes.reduce(0) { (($0 * 31) + Int($1)) % allCases.count }
        }
        return allCases[index]
    }
}
