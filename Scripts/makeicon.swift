#!/usr/bin/env swift
// Draws the Kuori app icon at every size macOS asks for and emits an .iconset.
// Pure AppKit so the repo needs no design tooling to rebuild the artwork.
//
// "Kuori" is Finnish for peel / rind. The mark is one strip of citrus peel
// pared away in a curl — thick at the cut base, tapering to a loose tip — with
// the bare fruit at its centre. A whole thing turned into another form.
import AppKit

func rot90(_ v: CGVector) -> CGVector { CGVector(dx: -v.dy, dy: v.dx) }
func norm(_ v: CGVector) -> CGVector {
    let m = max(sqrt(v.dx * v.dx + v.dy * v.dy), 0.0001)
    return CGVector(dx: v.dx / m, dy: v.dy / m)
}

func drawIcon(size s: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // Dark squircle ground.
    let squircle = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.055, dy: s * 0.055),
                                xRadius: s * 0.225, yRadius: s * 0.225)
    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(calibratedWhite: 0.16, alpha: 1),
                        NSColor(calibratedWhite: 0.06, alpha: 1)])!.draw(in: rect, angle: -90)

    let c = CGPoint(x: s * 0.5, y: s * 0.505)

    // Centreline of the peel: a loose spiral, a bit over one turn.
    let turns = 1.28
    let thetaMax = CGFloat(turns * 2 * .pi)
    let rStart = s * 0.360          // cut base, outer
    let rEnd   = s * 0.140          // loose tip, near the fruit
    let hwBase = s * 0.058          // half-width at the base
    let hwTip  = s * 0.016          // half-width at the tip
    let startAngle: CGFloat = .pi * 0.62   // where the cut sits (upper-left)

    let n = 260
    func centre(_ t: CGFloat) -> CGPoint {
        let theta = startAngle + thetaMax * t
        let r = rStart - (rStart - rEnd) * t
        return CGPoint(x: c.x + cos(theta) * r, y: c.y + sin(theta) * r)
    }
    var outer: [CGPoint] = [], inner: [CGPoint] = [], mid: [CGPoint] = []
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let p = centre(t)
        let ahead = centre(min(1, t + 0.004)), back = centre(max(0, t - 0.004))
        let nrm = norm(rot90(CGVector(dx: ahead.x - back.x, dy: ahead.y - back.y)))
        let hw = hwBase + (hwTip - hwBase) * pow(t, 0.85)
        outer.append(CGPoint(x: p.x + nrm.dx * hw, y: p.y + nrm.dy * hw))
        inner.append(CGPoint(x: p.x - nrm.dx * hw, y: p.y - nrm.dy * hw))
        mid.append(p)
    }

    // Rind body — filled ribbon (outer edge forward, round the tip, inner edge back).
    let ribbon = NSBezierPath()
    ribbon.move(to: outer[0])
    for p in outer.dropFirst() { ribbon.line(to: p) }
    for p in inner.reversed() { ribbon.line(to: p) }
    ribbon.close()
    ctx.saveGState()
    ribbon.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 1.00, green: 0.64, blue: 0.16, alpha: 1),
                        NSColor(calibratedRed: 0.97, green: 0.47, blue: 0.06, alpha: 1)])!
        .draw(in: rect, angle: -60)
    ctx.restoreGState()

    // Pith: a thin pale line hugging the inner edge.
    let pith = NSBezierPath()
    pith.lineWidth = max(1, s * 0.012)
    pith.lineCapStyle = .round
    pith.lineJoinStyle = .round
    pith.move(to: inner[0])
    for p in inner.dropFirst() { pith.line(to: p) }
    NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.66, alpha: 0.92).setStroke()
    pith.stroke()

    // Bare fruit at the centre, sitting just inside the tip of the peel.
    let fr = s * 0.083
    NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.68, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: c.x - fr, y: c.y - fr, width: fr * 2, height: fr * 2)).fill()
    let seg = NSBezierPath()
    seg.lineWidth = max(0.75, s * 0.008)
    NSColor(calibratedRed: 0.90, green: 0.58, blue: 0.18, alpha: 0.55).setStroke()
    for a in stride(from: 0.0, to: 180.0, by: 30.0) {
        seg.move(to: CGPoint(x: c.x - cos(a * .pi / 180) * fr, y: c.y - sin(a * .pi / 180) * fr))
        seg.line(to: CGPoint(x: c.x + cos(a * .pi / 180) * fr, y: c.y + sin(a * .pi / 180) * fr))
    }
    seg.stroke()

    ctx.restoreGState()
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
