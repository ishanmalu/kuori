#!/usr/bin/env swift
// Draws the Kuori app icon at every size macOS asks for and emits an .iconset.
// Pure AppKit so the repo needs no design tooling to rebuild the artwork.
//
// "Kuori" is Finnish for peel / rind. The mark is one clean strip of peel
// curling off the fruit — a single white ribbon on a near-black squircle,
// tapering from the cut base to a loose tip, with the bare fruit as a dot at
// its centre. No colour, no gradient, no ornament.
import AppKit

func rot90(_ v: CGVector) -> CGVector { CGVector(dx: -v.dy, dy: v.dx) }
func unit(_ v: CGVector) -> CGVector {
    let m = max((v.dx * v.dx + v.dy * v.dy).squareRoot(), 0.0001)
    return CGVector(dx: v.dx / m, dy: v.dy / m)
}

func drawIcon(size s: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // Flat near-black squircle.
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.055, dy: s * 0.055),
                 xRadius: s * 0.225, yRadius: s * 0.225).fill()

    let c = CGPoint(x: s * 0.5, y: s * 0.505)
    let turns: CGFloat = 1.24
    let thetaMax = turns * 2 * .pi
    let rStart = s * 0.350
    let rEnd   = s * 0.150
    let hwBase = s * 0.050
    let hwTip  = s * 0.013
    let startAngle: CGFloat = .pi * 0.60

    let n = 260
    func centre(_ t: CGFloat) -> CGPoint {
        let theta = startAngle + thetaMax * t
        let r = rStart - (rStart - rEnd) * t
        return CGPoint(x: c.x + cos(theta) * r, y: c.y + sin(theta) * r)
    }
    var outer: [CGPoint] = [], inner: [CGPoint] = []
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let p = centre(t)
        let a = centre(min(1, t + 0.004)), b = centre(max(0, t - 0.004))
        let nrm = unit(rot90(CGVector(dx: a.x - b.x, dy: a.y - b.y)))
        let hw = hwBase + (hwTip - hwBase) * pow(t, 0.85)
        outer.append(CGPoint(x: p.x + nrm.dx * hw, y: p.y + nrm.dy * hw))
        inner.append(CGPoint(x: p.x - nrm.dx * hw, y: p.y - nrm.dy * hw))
    }

    let ribbon = NSBezierPath()
    ribbon.move(to: outer[0])
    for p in outer.dropFirst() { ribbon.line(to: p) }
    for p in inner.reversed() { ribbon.line(to: p) }
    ribbon.close()
    NSColor.white.setFill()
    ribbon.fill()

    // Bare fruit: a plain dot, with a small gap to the peel tip so the two read apart.
    let fr = s * 0.052
    NSBezierPath(ovalIn: CGRect(x: c.x - fr, y: c.y - fr, width: fr * 2, height: fr * 2)).fill()

    image.unlockFocus()
    return image
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let setDir = "\(outDir)/Kuori.iconset"
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
