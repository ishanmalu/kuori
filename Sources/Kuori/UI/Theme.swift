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

    // MARK: glass
    //
    // The wheel sits on a live blur of whatever is behind it, so its own fills
    // have to stay thin or the blur is wasted. These are the tints that go over
    // it: a wash to lift the disc off the desktop, a bright top rim and a dark
    // bottom rim to read as a curved edge catching light.

    /// Tint laid over the blur. Barely there in dark, slightly milky in light.
    static var glassTint: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 0.16, alpha: 0.42)
                                       : NSColor(calibratedWhite: 1.0, alpha: 0.12) }
    }
    /// The lit edge, strongest at the top of the curve.
    static var specular: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.30)
                                       : NSColor(calibratedWhite: 1.0, alpha: 0.85) }
    }
    /// The shaded edge underneath, which is what makes it read as thick.
    static var glassEdge: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 0.0, alpha: 0.38)
                                       : NSColor(calibratedWhite: 0.35, alpha: 0.22) }
    }
    /// Resting petal fill — glass, not paint.
    static var petalRest: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.09)
                                       : NSColor(calibratedWhite: 1.0, alpha: 0.62) }
    }
    /// Hub fill, a touch denser than the disc so the thumbnail has a seat.
    static var hubFill: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 0.13, alpha: 0.78)
                                       : NSColor(calibratedWhite: 1.0, alpha: 0.72) }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
