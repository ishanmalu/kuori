import AppKit

/// Perch's visual language — translucent surfaces, hairline strokes, one accent
/// threaded through every active state — wearing a daisy's colours: white
/// petals around a yellow centre.
enum Theme {
    static let corner: CGFloat = 13
    static let tileCorner: CGFloat = 8
    static let pad: CGFloat = 22

    /// The accent: the flower's centre. Warm enough to glow against both a white
    /// petal and a dark desktop, and dark enough that near-black text sits on it
    /// legibly — a paler lemon fails that second test.
    static let accent = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.16, alpha: 1)
    /// A half-step deeper, for the shaded side of the centre.
    static let accentDeep = NSColor(srgbRed: 0.98, green: 0.68, blue: 0.09, alpha: 1)

    /// Text and icons that sit on top of the accent.
    static let onAccent = NSColor(srgbRed: 0.20, green: 0.13, blue: 0.0, alpha: 1)

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
    /// Resting petal — white in both appearances, because that is the whole
    /// point of the name. It has to be nearly opaque: a translucent white over a
    /// dark desktop turns grey, and grey petals are not a daisy. The glass shows
    /// in the gaps between them and around the rim instead.
    static var petalRest: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.90)
                                       : NSColor(calibratedWhite: 1.0, alpha: 0.86) }
    }
    /// Petal text. On a white petal that has to be ink, in either appearance.
    static var onPetal: NSColor {
        NSColor(name: nil) { $0.isDark ? NSColor(calibratedWhite: 0.10, alpha: 1)
                                       : NSColor(calibratedWhite: 0.07, alpha: 1) }
    }
    /// The centre of the flower. A thumbnail covers it, so this is what shows
    /// when there isn't one.
    static var hubFill: NSColor { accent }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
