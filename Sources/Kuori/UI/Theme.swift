import AppKit

/// One ink, one paper. No accent, no category colour — the UI is black and
/// white and follows the system light/dark appearance.
enum Theme {
    static let corner: CGFloat = 12
    static let tileCorner: CGFloat = 8
    static let pad: CGFloat = 22
    static let tileGap: CGFloat = 7
    static let tileWidth: CGFloat = 76
    static let tileHeight: CGFloat = 30

    static var paper: NSColor { NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 0.09, alpha: 1) : .white } }
    static var ink: NSColor { NSColor(name: nil) { $0.isDark ? .white : NSColor(calibratedWhite: 0.06, alpha: 1) } }
    static var inkFaint: NSColor { ink.withAlphaComponent(0.55) }
    static var hairline: NSColor { ink.withAlphaComponent(0.22) }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
