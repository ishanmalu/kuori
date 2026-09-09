import AppKit
import UniformTypeIdentifiers

/// The floating HUD — a radial wheel, like Tangerine. Drop files; the source
/// sits in the hub and the targets fan out as petals. Click a petal, or move
/// with the arrow keys and press ↵. ⌥ swaps Convert → Tools; ⇥ cycles
/// Convert / Tools / Recipes. Monochrome, one ink / one paper.
final class DropPanel: NSPanel {
    static let shared = DropPanel()

    private let hud = WheelHUD()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 404),
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
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2 + 30))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(hud)
    }

    func load(urls: [URL]) {
        showCentered()
        hud.accept(urls)
    }

    func fitToContent() {}   // fixed-size wheel

    /// Used only by `--shot-ui` to render a non-default mode headlessly.
    func previewMode(_ name: String) { hud.forceMode(name) }
}

// MARK: - Wheel model

private struct WheelItem {
    let title: String
    let symbol: String?
    let run: () -> Void
}

private final class WheelHUD: NSView {
    weak var owner: DropPanel?

    private enum Mode: CaseIterable { case convert, tools, recipes }
    private var stickyMode: Mode?
    private var optionHeld = false
    private var mode: Mode { optionHeld ? .tools : (stickyMode ?? .convert) }

    private var inputs: [URL] = []
    private var formats: [Format] = []
    private var items: [WheelItem] = []
    private var focus = 0
    private var hover: Int?
    private var presetParent: Tool?
    private var running = false
    private var progress: Double = 0
    private var statusText = ""

    // geometry
    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY + 6) }
    private let discR: CGFloat = 150
    private let innerR: CGFloat = 70
    private let outerR: CGFloat = 142
    private var midR: CGFloat { (innerR + outerR) / 2 }
    private var petalThickness: CGFloat { outerR - innerR }
    private let petalGap: CGFloat = 0.09   // radians between petals

    override init(frame f: NSRect) {
        super.init(frame: f)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        resetEmpty()
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

    // MARK: state

    private func resetEmpty() {
        inputs = []; formats = []; items = []; presetParent = nil
        statusText = ""
        needsDisplay = true
    }

    func accept(_ urls: [URL]) {
        inputs = urls
        formats = urls.compactMap { Formats.byURL($0) }
        presetParent = nil
        running = false; progress = 0; statusText = ""
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
        case .tools:   items = presetParent != nil ? presetItems(presetParent!) : toolItems()
        case .recipes: items = recipeItems()
        }
        focus = min(focus, max(0, items.count - 1))
        needsDisplay = true
    }

    private func convertItems() -> [WheelItem] {
        let perFile = inputs.map { url -> Set<String> in
            guard let f = Formats.byURL(url) else { return [] }
            return Set(Engine.targets(for: f).map(\.id))
        }
        let shared = perFile.dropFirst().reduce(perFile.first ?? []) { $0.intersection($1) }
        let targets = shared.compactMap { Formats.byID[$0] }
            .filter { $0.id != "folder" || inputs.allSatisfy { Formats.byURL($0)?.category == .archive } }
            .sorted { ($0.category.rawValue, $0.label) < ($1.category.rawValue, $1.label) }
        return targets.map { fmt in
            WheelItem(title: fmt.label, symbol: nil) { [weak self] in self?.runConvert(to: fmt) }
        }
    }

    private func toolItems() -> [WheelItem] {
        Tool.allCases.filter { $0.applies(to: formats, count: inputs.count) }.map { t in
            WheelItem(title: t.wheelLabel, symbol: t.symbol) { [weak self] in self?.pickTool(t) }
        }
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
                if first == nil { first = out }
                try Engine.run(input: input, to: target, output: out, opts: ConvertOptions())
                report(i + 1)
            }
            return (first, "\(files.count) → \(target.label)")
        }
    }

    private func runTool(_ tool: Tool, preset: ToolPreset?) {
        let files = inputs
        let total = tool == .pdfMerge ? 1 : files.count
        run(count: total) { report in
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

    private func run(count: Int, _ work: @escaping (_ report: @escaping (Int) -> Void) throws -> (URL?, String)) {
        guard !running else { return }
        running = true; progress = 0; statusText = ""; needsDisplay = true
        let q = DispatchQueue(label: "kuori.run", qos: .userInitiated)
        q.async { [weak self] in
            let report: (Int) -> Void = { done in
                DispatchQueue.main.async { self?.progress = Double(done) / Double(max(1, count)); self?.needsDisplay = true }
            }
            do {
                let (reveal, summary) = try work(report)
                DispatchQueue.main.async {
                    self?.progress = 1; self?.statusText = summary; self?.needsDisplay = true
                    if let reveal { NSWorkspace.shared.activateFileViewerSelecting([reveal]) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self?.owner?.orderOut(nil); self?.finishRun()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusText = error.localizedDescription
                    self?.running = false; self?.progress = 0; self?.needsDisplay = true
                }
            }
        }
    }

    private func finishRun() { running = false; progress = 0; statusText = ""; needsDisplay = true }

    // MARK: geometry helpers

    /// Bisector angle for petal `i`, math orientation (from +x, ccw), index 0 at 12 o'clock.
    private func angle(_ i: Int) -> CGFloat {
        let n = max(1, items.count)
        return .pi / 2 - CGFloat(i) * (2 * .pi / CGFloat(n))
    }

    private var petalHalfAngle: CGFloat {
        let n = max(1, items.count)
        return max(0.14, .pi / CGFloat(n) - petalGap / 2)
    }

    private func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
    }

    /// A rounded, gently-flared annular segment — a citrus wedge that hugs the ring.
    private func petalPath(_ i: Int) -> NSBezierPath {
        let a = angle(i), ha = petalHalfAngle
        let pts = [
            polar(innerR, a - ha), polar(innerR, a), polar(innerR, a + ha),
            polar(outerR, a + ha), polar(outerR, a), polar(outerR, a - ha),
        ]
        let r: CGFloat = 9
        let path = NSBezierPath()
        func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
        path.move(to: mid(pts[pts.count - 1], pts[0]))
        for k in pts.indices {
            path.appendArc(from: pts[k], to: pts[(k + 1) % pts.count], radius: r)
        }
        path.close()
        return path
    }

    private func petalIndex(at p: CGPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = p.x - center.x, dy = p.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= innerR - 6, r <= outerR + 6 else { return nil }
        let ang = atan2(dy, dx)
        let ha = petalHalfAngle
        for i in items.indices {
            var d = ang - angle(i)
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            if abs(d) <= ha + petalGap * 0.4 { return i }
        }
        return nil
    }

    // MARK: paint

    override func draw(_ dirty: NSRect) {
        // card
        Theme.paper.setFill()
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 18, yRadius: 18)
        card.fill()
        card.lineWidth = 1; Theme.hairline.setStroke(); card.stroke()

        // top mode label
        drawCentered(modeLabel(), y: bounds.maxY - 26, size: 10, weight: .semibold, color: Theme.inkFaint, tracking: 1.4)

        guard !inputs.isEmpty else {
            let ring = NSBezierPath(ovalIn: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))
            ring.lineWidth = 1.5
            ring.setLineDash([6, 5], count: 2, phase: 0)
            Theme.hairline.setStroke(); ring.stroke()
            drawCentered("Drop files", y: center.y + 4, size: 14, weight: .semibold, color: Theme.ink)
            drawCentered("or ⌘V paste", y: center.y - 16, size: 11, weight: .regular, color: Theme.inkFaint)
            return
        }

        // faint disc behind the petals
        let disc = NSBezierPath(ovalIn: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))
        Theme.ink.withAlphaComponent(0.035).setFill(); disc.fill()

        if items.isEmpty {
            drawCentered("nothing converts", y: center.y + 6, size: 12, weight: .medium, color: Theme.ink)
            drawCentered("this selection", y: center.y - 12, size: 12, weight: .medium, color: Theme.ink)
        } else {
            for i in items.indices { drawPetal(i) }
        }

        drawHub()
        drawCaption()
    }

    private func drawPetal(_ i: Int) {
        let active = (hover ?? focus) == i
        let petal = petalPath(i)

        if active {
            Theme.ink.setFill()
        } else {
            Theme.ink.withAlphaComponent(0.06).setFill()
        }
        petal.fill()
        if running { (active ? Theme.paper : Theme.ink).withAlphaComponent(0.3).setFill(); petal.fill() }

        let item = items[i]
        let fg = active ? Theme.paper : Theme.ink
        let a = angle(i)
        let p = polar(midR + 5, a)
        var labelY = p.y
        if let sym = item.symbol,
           let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
            img.isTemplate = true
            let s: CGFloat = 14
            fg.set()
            img.draw(in: NSRect(x: p.x - s / 2, y: p.y + 4, width: s, height: s),
                     from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            labelY = p.y - 10
        }
        drawCentered(item.title, at: CGPoint(x: p.x, y: labelY), size: 10.5, weight: .semibold,
                     color: fg, tracking: 0.2, maxWidth: 88)
    }

    private func drawHub() {
        let w: CGFloat = 96, h: CGFloat = 46
        let r = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let hub = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        Theme.paper.setFill(); hub.fill()
        Theme.hairline.setStroke(); hub.lineWidth = 1; hub.stroke()

        let label: String
        if running { label = "\(Int(progress * 100))%" }
        else if presetParent != nil { label = presetParent!.label.uppercased() }
        else if !inputs.isEmpty { label = focusTitle() ?? hubFallback() }
        else { label = "" }
        drawCentered(label, at: CGPoint(x: center.x, y: center.y - 5), size: 12, weight: .semibold, color: Theme.ink)
    }

    private func drawCaption() {
        let text: String
        if !statusText.isEmpty { text = statusText }
        else if items.isEmpty { text = "" }
        else {
            switch mode {
            case .convert: text = "Convert to \(focusTitle() ?? "")"
            case .tools:   text = presetParent != nil ? "\(presetParent!.label) · \(focusTitle() ?? "")" : (focusTitle() ?? "")
            case .recipes: text = "Recipe · \(focusTitle() ?? "")"
            }
        }
        drawCentered(text, y: 30, size: 11, weight: .regular, color: Theme.inkFaint)
        drawCentered("↔ move   ↵ run   ⌥ tools   ⇥ mode   esc", y: 14, size: 9, weight: .regular, color: Theme.inkFaint.withAlphaComponent(0.7))
    }

    private func modeLabel() -> String {
        switch mode {
        case .convert: return inputs.count <= 1 ? (inputs.first?.lastPathComponent ?? "CONVERT") : "\(inputs.count) FILES"
        case .tools:   return "TOOLS"
        case .recipes: return "RECIPES"
        }
    }
    private func focusTitle() -> String? { items.indices.contains(focus) ? items[focus].title : nil }
    private func hubFallback() -> String { formats.first?.label ?? "" }

    private func drawCentered(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
                              color: NSColor, tracking: CGFloat = 0) {
        drawCentered(s, at: CGPoint(x: bounds.midX, y: y), size: size, weight: weight, color: color, tracking: tracking)
    }
    private func drawCentered(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight,
                              color: NSColor, tracking: CGFloat = 0, maxWidth: CGFloat = 400) {
        guard !s.isEmpty else { return }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]
        if tracking != 0 { attrs[.kern] = tracking }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        para.alignment = .center
        attrs[.paragraphStyle] = para
        let str = NSAttributedString(string: s, attributes: attrs)
        let box = str.boundingRect(with: NSSize(width: maxWidth, height: 60),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading])
        str.draw(with: NSRect(x: p.x - box.width / 2, y: p.y - box.height / 2,
                              width: box.width, height: box.height),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    // MARK: input

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let idx = petalIndex(at: p)
        if idx != hover { hover = idx; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) { if hover != nil { hover = nil; needsDisplay = true } }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let i = petalIndex(at: p), !running { focus = i; items[i].run() }
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53:                                             // esc
            if presetParent != nil { presetParent = nil; rebuild() } else { owner?.orderOut(nil) }
        case 123, 126:                                       // ← / ↑  prev
            step(-1)
        case 124, 125:                                       // → / ↓  next
            step(+1)
        case 36, 76:                                         // return / enter
            if !running, items.indices.contains(focus) { items[focus].run() }
        case 48:                                             // tab
            cycleMode()
        default:
            if let ch = e.charactersIgnoringModifiers, ch == "v", e.modifierFlags.contains(.command) { pasteFiles() }
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
        if held != optionHeld { optionHeld = held; presetParent = nil; rebuild() }
        super.flagsChanged(with: e)
    }

    private func pasteFiles() {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
            accept(urls)
        }
    }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return false }
        accept(urls)
        return true
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

    /// Short enough to sit inside a petal; `\n` splits the wide ones onto two lines.
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
