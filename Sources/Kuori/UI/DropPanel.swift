import AppKit
import UniformTypeIdentifiers

/// The radial wheel. The source file sits in the hub, targets fan out as petals.
/// Drop a file onto a petal, or move with the arrow keys and press return.
/// ⌥ swaps Convert for Tools; ⇥ cycles Convert / Tools / Recipes.
final class DropPanel: NSPanel {
    static let shared = DropPanel()

    private let hud = WheelHUD()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = hud
        hud.owner = self
    }

    override var canBecomeKey: Bool { true }

    func toggle() { isVisible ? orderOut(nil) : showCentered() }

    func showCentered() {
        if let vf = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2, y: vf.midY - frame.height / 2 + 30))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(hud)
    }

    /// From the menu, Services, or a paste — an interactive open.
    func load(urls: [URL]) {
        showCentered()
        hud.accept(urls)
    }

    /// From `DragMonitor`: a Shift-drag is in progress. Appear under the cursor
    /// without taking focus, so the drag keeps running and can land on a petal.
    func beginDrop(urls: [URL], at point: NSPoint) {
        position(around: point)
        hud.dragSummoned = true
        orderFront(nil)
        hud.accept(urls)
    }

    func dismissIfDragSummoned() {
        if hud.dragSummoned { hud.dragSummoned = false; orderOut(nil) }
    }

    private func position(around p: NSPoint) {
        var o = NSPoint(x: p.x - frame.width / 2, y: p.y - frame.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            o.x = min(max(o.x, vf.minX + 8), vf.maxX - frame.width - 8)
            o.y = min(max(o.y, vf.minY + 8), vf.maxY - frame.height - 8)
        }
        setFrameOrigin(o)
    }

    /// `--shot-ui` only.
    func previewMode(_ name: String) { hud.forceMode(name) }
}

private struct WheelItem {
    let title: String
    let symbol: String?
    let run: () -> Void
}

private final class WheelHUD: NSView {
    weak var owner: DropPanel?
    var dragSummoned = false

    private enum Mode: CaseIterable { case convert, tools, recipes }
    private var stickyMode: Mode?
    private var optionHeld = false
    private var mode: Mode { optionHeld ? .tools : (stickyMode ?? .convert) }

    private var inputs: [URL] = []
    private var formats: [Format] = []
    private var thumb: NSImage?
    private var items: [WheelItem] = []
    private var focus = 0
    private var hover: Int?
    private var presetParent: Tool?
    private var running = false
    private var progress = 0.0

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    private let discR: CGFloat = 143
    private let hubR: CGFloat = 44
    private let innerR: CGFloat = 50
    private let outerR: CGFloat = 134
    private var midR: CGFloat { (innerR + outerR) / 2 }
    private let petalGap: CGFloat = 0.10

    override init(frame f: NSRect) {
        super.init(frame: f)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    // MARK: contents

    func accept(_ urls: [URL]) {
        guard urls != inputs else { return }
        inputs = urls
        formats = urls.compactMap { Formats.byURL($0) }
        thumb = urls.count == 1 ? Self.thumbnail(urls[0], side: hubR * 2) : nil
        presetParent = nil
        running = false
        progress = 0
        rebuild()
    }

    fileprivate func forceMode(_ name: String) {
        stickyMode = ["tools": .tools, "recipes": .recipes][name]
        rebuild()
    }

    private func cycleMode() {
        let order = Mode.allCases
        stickyMode = order[(order.firstIndex(of: stickyMode ?? .convert)! + 1) % order.count]
        presetParent = nil
        rebuild()
    }

    private func rebuild() {
        guard !inputs.isEmpty else { needsDisplay = true; return }
        switch mode {
        case .convert: items = convertItems()
        case .tools:   items = presetParent.map(presetItems) ?? toolItems()
        case .recipes: items = recipeItems()
        }
        focus = min(focus, max(0, items.count - 1))
        needsDisplay = true
    }

    private func convertItems() -> [WheelItem] {
        let routes = inputs.map { url -> Set<String> in
            guard let f = Formats.byURL(url) else { return [] }
            return Set(Engine.targets(for: f).map(\.id))
        }
        let shared = routes.dropFirst().reduce(routes.first ?? []) { $0.intersection($1) }
        return shared.compactMap { Formats.byID[$0] }
            .filter { $0.id != "folder" || inputs.allSatisfy { Formats.byURL($0)?.category == .archive } }
            .sorted { ($0.category.rawValue, $0.label) < ($1.category.rawValue, $1.label) }
            .map { fmt in WheelItem(title: fmt.label, symbol: nil) { [weak self] in self?.runConvert(to: fmt) } }
    }

    private func toolItems() -> [WheelItem] {
        Tool.allCases
            .filter { $0.applies(to: formats, count: inputs.count) }
            .map { t in WheelItem(title: t.wheelLabel, symbol: t.symbol) { [weak self] in self?.pickTool(t) } }
    }

    private func presetItems(_ t: Tool) -> [WheelItem] {
        t.presets.map { p in
            WheelItem(title: p.label.uppercased(), symbol: t.symbol) { [weak self] in self?.runTool(t, preset: p) }
        }
    }

    private func recipeItems() -> [WheelItem] {
        Recipes.all().map { r in
            let short = r.name.count > 12 ? String(r.name.prefix(11)) + "…" : r.name
            return WheelItem(title: short.uppercased(), symbol: "wand.and.stars") { [weak self] in self?.runRecipe(r) }
        }
    }

    private func pickTool(_ t: Tool) {
        if t.presets.isEmpty { runTool(t, preset: nil); return }
        presetParent = t
        focus = 0
        rebuild()
    }

    // MARK: run

    private func runConvert(to target: Format) {
        let files = inputs
        run(count: files.count) { report in
            var first: URL?
            for (i, input) in files.enumerated() {
                guard let out = Naming.output(for: input, target: target, into: nil, collision: .suffix) else { continue }
                let written = try Engine.run(input: input, to: target, output: out, opts: ConvertOptions())
                if first == nil { first = written }
                report(i + 1)
            }
            return (first, "\(files.count) → \(target.label)")
        }
    }

    private func runTool(_ tool: Tool, preset: ToolPreset?) {
        let files = inputs
        let steps = (tool == .pdfMerge || tool == .pdfSplit) ? 1 : files.count
        run(count: steps) { report in
            if tool == .pdfMerge || tool == .pdfSplit {
                let outs = try ToolRunner.run(tool, inputs: files, params: ToolRunner.Params(preset: preset))
                report(1)
                return (outs.first, tool.label)
            }
            var first: URL?
            for (i, input) in files.enumerated() {
                let outs = try ToolRunner.run(tool, inputs: [input], params: ToolRunner.Params(preset: preset))
                if first == nil { first = outs.first }
                report(i + 1)
            }
            return (first, "\(tool.label) · \(files.count)")
        }
    }

    private func runRecipe(_ recipe: Recipe) {
        let files = inputs
        run(count: files.count) { report in
            var first: URL?
            for (i, input) in files.enumerated() {
                let out = try RecipeRunner.run(recipe, input: input, into: nil)
                if first == nil { first = out }
                report(i + 1)
            }
            return (first, "\(recipe.name) · \(files.count)")
        }
    }

    private func run(count: Int,
                     _ work: @escaping (_ report: @escaping (Int) -> Void) throws -> (URL?, String)) {
        guard !running else { return }
        running = true
        progress = 0
        needsDisplay = true

        DispatchQueue(label: "kuori.run", qos: .userInitiated).async { [weak self] in
            let report: (Int) -> Void = { done in
                DispatchQueue.main.async {
                    self?.progress = Double(done) / Double(max(1, count))
                    self?.needsDisplay = true
                }
            }
            do {
                let (reveal, _) = try work(report)
                DispatchQueue.main.async {
                    self?.progress = 1
                    self?.needsDisplay = true
                    if let reveal { NSWorkspace.shared.activateFileViewerSelecting([reveal]) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self?.owner?.orderOut(nil)
                        self?.running = false
                        self?.progress = 0
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.running = false
                    self?.progress = 0
                    self?.needsDisplay = true
                    NSSound.beep()
                }
            }
        }
    }

    // MARK: geometry

    /// Bisector of petal `i`, measured from +x counter-clockwise, index 0 at 12 o'clock.
    private func angle(_ i: Int) -> CGFloat {
        .pi / 2 - CGFloat(i) * (2 * .pi / CGFloat(max(1, items.count)))
    }

    private var petalHalfAngle: CGFloat {
        max(0.14, .pi / CGFloat(max(1, items.count)) - petalGap / 2)
    }

    private func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
    }

    private func petalPath(_ i: Int) -> NSBezierPath {
        let a = angle(i), ha = petalHalfAngle
        let pts = [
            polar(innerR, a - ha), polar(innerR, a), polar(innerR, a + ha),
            polar(outerR, a + ha), polar(outerR, a), polar(outerR, a - ha),
        ]
        let path = NSBezierPath()
        func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
        path.move(to: mid(pts[pts.count - 1], pts[0]))
        for k in pts.indices {
            path.appendArc(from: pts[k], to: pts[(k + 1) % pts.count], radius: 9)
        }
        path.close()
        return path
    }

    private func petalIndex(at p: CGPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = p.x - center.x, dy = p.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= innerR - 6, r <= outerR + 6 else { return nil }
        let ang = atan2(dy, dx), ha = petalHalfAngle
        for i in items.indices {
            var d = ang - angle(i)
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            if abs(d) <= ha + petalGap * 0.4 { return i }
        }
        return nil
    }

    // MARK: paint

    private var discRect: NSRect {
        NSRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2)
    }

    override func draw(_ dirty: NSRect) {
        let disc = NSBezierPath(ovalIn: discRect)

        guard !inputs.isEmpty else {
            Theme.paper.withAlphaComponent(0.9).setFill()
            disc.fill()
            disc.lineWidth = 1.5
            disc.setLineDash([6, 5], count: 2, phase: 0)
            Theme.hairline.setStroke()
            disc.stroke()
            text("Drop", at: CGPoint(x: center.x, y: center.y + 9), 14, .semibold, Theme.ink)
            text("files", at: CGPoint(x: center.x, y: center.y - 9), 14, .semibold, Theme.ink)
            return
        }

        Theme.paper.withAlphaComponent(0.98).setFill()
        disc.fill()
        Theme.hairline.withAlphaComponent(0.7).setStroke()
        disc.lineWidth = 1
        disc.stroke()

        if items.isEmpty {
            text("no route for", at: CGPoint(x: center.x, y: center.y + 8), 12, .medium, Theme.ink)
            text("this selection", at: CGPoint(x: center.x, y: center.y - 10), 12, .medium, Theme.ink)
        } else {
            for i in items.indices { drawPetal(i) }
        }
        drawHub()
    }

    private func drawPetal(_ i: Int) {
        let active = (hover ?? focus) == i
        let petal = petalPath(i)

        (active ? Theme.ink : Theme.ink.withAlphaComponent(0.06)).setFill()
        petal.fill()
        if running {
            (active ? Theme.paper : Theme.ink).withAlphaComponent(0.3).setFill()
            petal.fill()
        }

        let item = items[i]
        let fg = active ? Theme.paper : Theme.ink
        let p = polar(midR + 5, angle(i))
        var labelY = p.y
        if let name = item.symbol,
           let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
            icon.isTemplate = true
            fg.set()
            icon.draw(in: NSRect(x: p.x - 7, y: p.y + 4, width: 14, height: 14),
                      from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            labelY = p.y - 10
        }
        text(item.title, at: CGPoint(x: p.x, y: labelY), 10.5, .semibold, fg, tracking: 0.2, maxWidth: 88)
    }

    private func drawHub() {
        let box = NSRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)
        let hub = NSBezierPath(ovalIn: box)
        Theme.paper.setFill()
        hub.fill()

        if let thumb {
            NSGraphicsContext.saveGraphicsState()
            hub.addClip()
            thumb.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            text(sourceLabel(), at: CGPoint(x: center.x, y: center.y + 4), 12, .semibold, Theme.ink)
        }
        Theme.hairline.setStroke()
        hub.lineWidth = 1
        hub.stroke()

        let pill = running ? "\(Int(progress * 100))%"
            : presetParent.map { $0.label.uppercased() } ?? (focusTitle() ?? "")
        guard !pill.isEmpty else { return }
        let width = (pill as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width + 18
        let r = NSRect(x: center.x - width / 2, y: center.y - hubR + 6, width: width, height: 20)
        Theme.ink.setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        text(pill, at: CGPoint(x: r.midX, y: r.midY), 11, .semibold, Theme.paper)
    }

    private func sourceLabel() -> String {
        if inputs.count > 1 { return "\(inputs.count) FILES" }
        return formats.first?.label ?? inputs.first.map { $0.pathExtension.uppercased() } ?? ""
    }

    private func focusTitle() -> String? {
        let i = hover ?? focus
        return items.indices.contains(i) ? items[i].title.replacingOccurrences(of: "\n", with: " ") : nil
    }

    private func text(_ s: String, at p: CGPoint, _ size: CGFloat, _ weight: NSFont.Weight,
                      _ color: NSColor, tracking: CGFloat = 0, maxWidth: CGFloat = 400) {
        guard !s.isEmpty else { return }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        if tracking != 0 { attrs[.kern] = tracking }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        attrs[.paragraphStyle] = para
        let str = NSAttributedString(string: s, attributes: attrs)
        let box = str.boundingRect(with: NSSize(width: maxWidth, height: 60),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading])
        str.draw(with: NSRect(x: p.x - box.width / 2, y: p.y - box.height / 2, width: box.width, height: box.height),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func thumbnail(_ url: URL, side: CGFloat) -> NSImage? {
        guard let src = NSImage(contentsOf: url), src.size.width > 0, src.size.height > 0 else { return nil }
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        let scale = side / min(src.size.width, src.size.height)
        let w = src.size.width * scale, h = src.size.height * scale
        src.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        out.unlockFocus()
        return out
    }

    // MARK: input

    override func mouseMoved(with e: NSEvent) {
        let i = petalIndex(at: convert(e.locationInWindow, from: nil))
        if i != hover { hover = i; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) {
        if hover != nil { hover = nil; needsDisplay = true }
    }

    override func mouseDown(with e: NSEvent) {
        guard !running, let i = petalIndex(at: convert(e.locationInWindow, from: nil)) else { return }
        focus = i
        items[i].run()
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53:                                 // esc
            if presetParent != nil { presetParent = nil; rebuild() } else { owner?.orderOut(nil) }
        case 123, 126: step(-1)                   // ← ↑
        case 124, 125: step(+1)                   // → ↓
        case 36, 76:                             // return
            if !running, items.indices.contains(focus) { items[focus].run() }
        case 48: cycleMode()                     // tab
        default:
            if e.charactersIgnoringModifiers == "v", e.modifierFlags.contains(.command) { paste() }
            else { super.keyDown(with: e) }
        }
    }

    private func step(_ d: Int) {
        guard !items.isEmpty else { return }
        focus = (focus + d + items.count) % items.count
        needsDisplay = true
    }

    override func flagsChanged(with e: NSEvent) {
        let held = e.modifierFlags.contains(.option)
        if held != optionHeld {
            optionHeld = held
            presetParent = nil
            rebuild()
        }
        super.flagsChanged(with: e)
    }

    private func paste() {
        if let urls = Self.fileURLs(NSPasteboard.general), !urls.isEmpty { accept(urls) }
    }

    // MARK: drag

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        let i = petalIndex(at: convert(s.draggingLocation, from: nil))
        if i != hover { hover = i; needsDisplay = true }
        return .copy
    }

    override func draggingExited(_ s: NSDraggingInfo?) {
        if hover != nil { hover = nil; needsDisplay = true }
    }

    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let urls = Self.fileURLs(s.draggingPasteboard), !urls.isEmpty else { return false }
        dragSummoned = false
        accept(urls)
        if !running, let i = petalIndex(at: convert(s.draggingLocation, from: nil)) {
            focus = i
            items[i].run()
        } else {
            // Dropped on the disc, not a petal — leave it open and make it usable by keyboard.
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
        }
        return true
    }

    override func draggingEnded(_ s: NSDraggingInfo) {
        if dragSummoned {
            dragSummoned = false
            owner?.orderOut(nil)
        }
    }

    private static func fileURLs(_ pb: NSPasteboard) -> [URL]? {
        pb.readObjects(forClasses: [NSURL.self],
                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
    }
}

private extension Tool {
    var symbol: String {
        switch self {
        case .resize:           return "arrow.up.left.and.arrow.down.right"
        case .compress:         return "arrow.down.right.and.arrow.up.left"
        case .crop:             return "crop"
        case .stripMetadata:    return "tag.slash"
        case .trim:             return "scissors"
        case .ocr:              return "text.viewfinder"
        case .removeBackground: return "person.crop.rectangle.badge.xmark"
        case .pdfMerge:         return "doc.on.doc"
        case .pdfSplit:         return "square.split.1x2"
        }
    }

    /// Short label for a petal; `\n` breaks the wide ones onto two lines.
    var wheelLabel: String {
        switch self {
        case .resize:           return "RESIZE"
        case .compress:         return "COMPRESS"
        case .crop:             return "CROP"
        case .stripMetadata:    return "STRIP\nMETA"
        case .trim:             return "TRIM"
        case .ocr:              return "OCR"
        case .removeBackground: return "REMOVE\nBG"
        case .pdfMerge:         return "MERGE\nPDF"
        case .pdfSplit:         return "SPLIT\nPDF"
        }
    }
}
