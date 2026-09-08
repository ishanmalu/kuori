import AppKit

enum Theme {
    static let corner: CGFloat = 14
    static let tileCorner: CGFloat = 10
    static let pad: CGFloat = 16
    static let tileGap: CGFloat = 8

    static var panelBackground: NSColor { NSColor.windowBackgroundColor.withAlphaComponent(0.98) }
    static var tileIdle: NSColor { NSColor.controlColor }
    static var tileHot: NSColor { NSColor.controlAccentColor }

    static func categoryTint(_ c: Category) -> NSColor {
        switch c {
        case .image:    return NSColor.systemOrange
        case .video:    return NSColor.systemPurple
        case .audio:    return NSColor.systemPink
        case .document: return NSColor.systemBlue
        case .archive:  return NSColor.systemGreen
        }
    }
}
