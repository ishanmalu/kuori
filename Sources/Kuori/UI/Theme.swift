import AppKit

/// Perch's visual language — translucent surfaces, hairline strokes, one accent
/// threaded through every active state — with that accent set to neon.
enum Theme {
    static let corner: CGFloat = 13
    static let tileCorner: CGFloat = 8
    static let pad: CGFloat = 22

    /// The single accent. Low alpha for fills, higher for edges, full for text and glow.
    static let neon = NSColor(srgbRed: 0.28, green: 1.0, blue: 0.52, alpha: 1)

    static var paper: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 0.10, alpha: 1) : .white }
    }
    static var ink: NSColor {
        NSColor(name: nil) { $0.isDark ? .white : NSColor(calibratedWhite: 0.07, alpha: 1) }
    }
    static var inkFaint: NSColor { ink.withAlphaComponent(0.5) }
    static var hairline: NSColor { ink.withAlphaComponent(0.16) }
    static var cardFill: NSColor { ink.withAlphaComponent(0.055) }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
