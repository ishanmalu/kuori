#!/usr/bin/env swift
// Draws the Daisy app icon at every size macOS asks for and emits an .iconset.
// Pure AppKit so the repo needs no design tooling to rebuild the artwork.
//
// The mark is the app: eight white petals around a yellow centre, the same
// wheel you drop a file onto, on a near-black squircle. The petals are the
// wheel's own shape — a rounded wedge between two radii — so the icon and the
// UI are drawn from one geometry.
import AppKit

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

func drawIcon(size s: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // Flat near-black squircle.
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.055, dy: s * 0.055),
                 xRadius: s * 0.225, yRadius: s * 0.225).fill()

    let c = CGPoint(x: s * 0.5, y: s * 0.5)
    let petals = 8
    let innerR = s * 0.150
    let outerR = s * 0.400
    let gap: CGFloat = 0.16          // radians trimmed from each side of a petal
    let step = (.pi * 2) / CGFloat(petals)
    let half = step / 2 - gap / 2

    func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
        CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }

    NSColor.white.setFill()
    for i in 0..<petals {
        // Start at twelve o'clock so the icon has an axis of symmetry.
        let a = .pi / 2 - CGFloat(i) * step
        let corner = s * 0.055
        let petal = NSBezierPath()
        // Rounded corners come from appendArc(from:to:radius:), which is also
        // how the wheel draws its petals.
        let pts = [polar(outerR, a - half), polar(outerR, a + half),
                   polar(innerR, a + half), polar(innerR, a - half)]
        petal.move(to: midpoint(pts[3], pts[0]))
        for k in 0..<4 {
            petal.appendArc(from: pts[k], to: pts[(k + 1) % 4], radius: corner)
        }
        petal.close()
        petal.fill()
    }

    // The centre.
    let hubR = s * 0.118
    let hub = NSBezierPath(ovalIn: CGRect(x: c.x - hubR, y: c.y - hubR,
                                          width: hubR * 2, height: hubR * 2))
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.82, blue: 0.20, alpha: 1),
               ending: NSColor(srgbRed: 0.97, green: 0.66, blue: 0.07, alpha: 1))?
        .draw(in: hub, angle: -90)

    image.unlockFocus()
    return image
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let setDir = "\(outDir)/Daisy.iconset"
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
