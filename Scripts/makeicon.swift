#!/usr/bin/env swift
// Draws the Zest app icon at every size macOS asks for and emits an .iconset.
// Pure AppKit so the repo needs no design tooling to rebuild the artwork.
// A citrus wedge on a dark squircle: the "zest" is the bright rind arc.
import AppKit

func drawIcon(size s: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    let squircle = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.055, dy: s * 0.055),
                                xRadius: s * 0.225, yRadius: s * 0.225)
    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(calibratedWhite: 0.14, alpha: 1),
                        NSColor(calibratedWhite: 0.06, alpha: 1)])!.draw(in: rect, angle: -90)

    let cx = s * 0.5, cy = s * 0.46
    let r = s * 0.34

    // flesh wedge
    NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.13, alpha: 1).setFill()
    let wedge = NSBezierPath()
    wedge.move(to: CGPoint(x: cx, y: cy))
    wedge.appendArc(withCenter: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: 20, endAngle: 160)
    wedge.close()
    wedge.fill()

    // segment lines
    NSColor(calibratedWhite: 0.06, alpha: 1).setStroke()
    for a in stride(from: 35.0, through: 145.0, by: 27.5) {
        let p = NSBezierPath()
        p.lineWidth = s * 0.012
        p.move(to: CGPoint(x: cx, y: cy))
        p.line(to: CGPoint(x: cx + cos(a * .pi / 180) * r, y: cy + sin(a * .pi / 180) * r))
        p.stroke()
    }

    // bright rind arc — the "zest"
    NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.28, alpha: 1).setStroke()
    let rind = NSBezierPath()
    rind.lineWidth = s * 0.05
    rind.lineCapStyle = .round
    rind.appendArc(withCenter: CGPoint(x: cx, y: cy), radius: r * 1.12,
                   startAngle: 18, endAngle: 162)
    rind.stroke()

    // conversion arrows below the wedge
    NSColor.white.withAlphaComponent(0.92).setStroke()
    let arr = NSBezierPath()
    arr.lineWidth = s * 0.030
    arr.lineCapStyle = .round
    arr.lineJoinStyle = .round
    let ay = s * 0.24
    arr.move(to: CGPoint(x: s * 0.34, y: ay + s * 0.05))
    arr.line(to: CGPoint(x: s * 0.66, y: ay + s * 0.05))
    arr.move(to: CGPoint(x: s * 0.60, y: ay + s * 0.10))
    arr.line(to: CGPoint(x: s * 0.66, y: ay + s * 0.05))
    arr.line(to: CGPoint(x: s * 0.60, y: ay))
    arr.stroke()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let setDir = "\(outDir)/Zest.iconset"
try? FileManager.default.createDirectory(atPath: setDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    let img = drawIcon(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(setDir)/\(name).png"))
}
print("wrote \(setDir)")
