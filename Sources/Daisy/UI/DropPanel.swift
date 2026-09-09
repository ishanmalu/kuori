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

        // The wheel is glass: a live blur of the desktop behind it, clipped to
        // the disc, with the HUD's own translucent fills painted on top. The
        // mask is what keeps the blur circular — a rounded-rect layer mask
        // would be ignored by the behind-window blur.
        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.circleMask(diameter: WheelHUD.discDiameter)
        blur.autoresizingMask = [.width, .height]

        hud.frame = blur.bounds
        hud.autoresizingMask = [.width, .height]
        blur.addSubview(hud)
        contentView = blur
        hud.owner = self
    }

    /// A centred circle the blur view stretches around. Drawn with a cap inset
    /// so AppKit's nine-part stretching leaves the curve alone.
    private static func circleMask(diameter d: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: d / 2 - 1, left: d / 2 - 1,
                                       bottom: d / 2 - 1, right: d / 2 - 1)
        image.resizingMode = .stretch
        return image
    }

    override var canBecomeKey: Bool { true }

    func toggle() { isVisible ? orderOut(nil) : summon() }

    /// Hotkey / menu summon. If files are on the clipboard it loads them;
    /// otherwise it's an empty ring to drag a file onto.
    func summon() {
        centreOnScreen()
        if let urls = Self.clipboardFiles() { hud.accept(urls) }
        present()
    }

    func showCentered() { centreOnScreen(); present() }

    /// The wheel always lands dead centre of the active screen — one place to
    /// look for it, and a drag always has the same distance to travel.
    private func centreOnScreen() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: (vf.midX - frame.width / 2).rounded(),
                               y: (vf.midY - frame.height / 2).rounded()))
    }

    private func present() {
        let fresh = !isVisible
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(hud)
        if fresh { playEntrance() }
    }

    /// A short rise into place. The window fades while the content scales up
    /// from just under full size — enough to read as arriving rather than
    /// blinking on, and short enough that it never delays a drop.
    private func playEntrance() {
        guard let layer = contentView?.layer else { return }
        alphaValue = 0
        layer.transform = CATransform3DMakeScale(0.90, 0.90, 1)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.1, 0.3, 1)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 1
            layer.transform = CATransform3DIdentity
        }
    }

    private static func clipboardFiles() -> [URL]? {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                   options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return (urls?.isEmpty ?? true) ? nil : urls
    }

    /// From the menu, Services, or a paste — an interactive open.
    func load(urls: [URL]) {
        showCentered()
        hud.accept(urls)
    }

    private var dragDismiss: DispatchWorkItem?

    /// From `DragMonitor`: a Shift-drag is in progress somewhere. Appear in the
    /// middle without taking focus, so the drag keeps running. The HUD reads the
    /// dragged files once the drag enters it; if none does, we vanish.
    func beginDrop() {
        centreOnScreen()
        hud.armForDrag()
        orderFront(nil)

        // Mouse-up is what really dismisses this; the timer is only a backstop
        // for a drag whose release we never see.
        dragDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissIfDragSummoned() }
        dragDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func cancelDragDismiss() { dragDismiss?.cancel(); dragDismiss = nil }

    func dismissIfDragSummoned() {
        if hud.dragSummoned { hud.dragSummoned = false; orderOut(nil) }
    }

    /// Menu-bar "Convert File…": the wheel plus Finder's picker in one step.
    func summonAndChoose() {
        showCentered()
        hud.chooseFiles()
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
    /// Set when `inputs` came from expanding a dropped folder.
    private var folderInput: URL?
    /// Cursor is over the empty ring, which is one big button.
    private var hoveringEmpty = false
    private var running = false
    private var progress = 0.0
    private var errorText: String?
    private var errorClear: DispatchWorkItem?

    static let discDiameter: CGFloat = 286

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
        let (resolved, folder) = InputSet.expand(urls)
        guard resolved != inputs || folder != folderInput else { return }
        folderInput = folder
        inputs = resolved
        formats = resolved.compactMap { Formats.byURL($0) }
        thumb = resolved.count == 1 ? Self.thumbnail(resolved[0], side: hubR * 2)
              : folder.flatMap { Self.thumbnail($0, side: hubR * 2) }
        presetParent = nil
        running = false
        progress = 0
        rebuild()
    }

    /// Shown by `DragMonitor` before we know what's being dragged.
    func armForDrag() {
        resetIdle()
        dragSummoned = true
    }

    /// A conversion failed — say so on the wheel rather than only beeping.
    /// The petals stay put so the same drop can be retried.
    private func showError(_ message: String) {
        errorText = message
        needsDisplay = true
        errorClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.errorText = nil; self?.needsDisplay = true }
        errorClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    /// Back to the empty ring — after a conversion, or before a new drag.
    private func resetIdle() {
        errorClear?.cancel()
        errorText = nil
        inputs = []
        formats = []
        thumb = nil
        items = []
        presetParent = nil
        folderInput = nil
        hover = nil
        focus = 0
        running = false
        progress = 0
        dragSummoned = false
        hoveringEmpty = false
        needsDisplay = true
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
        var shared = routes.dropFirst().reduce(routes.first ?? []) { $0.intersection($1) }
        // An expanded folder can still be packed as a whole.
        if folderInput != nil, let folder = Formats.byID["folder"] {
            shared.formUnion(Engine.targets(for: folder).map(\.id))
        }
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
        // Packing an expanded folder acts on the folder, not on each file in it.
        if let folder = folderInput, target.category == .archive {
            run(count: 1) { report in
                guard let out = Naming.output(for: folder, target: target, into: nil, collision: .suffix) else {
                    throw ConvertError.badInput("Couldn't name the archive.")
                }
                let written = try Engine.run(input: folder, to: target, output: out, opts: ConvertOptions())
                report(1)
                return (written, "\(folder.lastPathComponent) → \(target.label)")
            }
            return
        }

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

        DispatchQueue(label: "daisy.run", qos: .userInitiated).async { [weak self] in
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        guard let self else { return }
                        // Came from a drag → get out of the way. Opened deliberately
                        // (hotkey, or clicked into) → stay, cleared, ready for the next file.
                        if self.window?.isKeyWindow != true { self.owner?.orderOut(nil) }
                        self.resetIdle()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.running = false
                    self.progress = 0
                    self.showError(error.localizedDescription)
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
            Theme.glassTint.setFill()
            disc.fill()
            drawRim()
            let dashed = NSBezierPath(ovalIn: discRect.insetBy(dx: 9, dy: 9))
            dashed.lineWidth = 1.5
            dashed.setLineDash([6, 6], count: 2, phase: 0)
            Theme.accent.withAlphaComponent(hoveringEmpty ? 0.75 : 0.42).setStroke()
            dashed.stroke()
            text("Drop files", at: CGPoint(x: center.x, y: center.y + 16), 14, .semibold, Theme.ink)
            text("or click to choose", at: CGPoint(x: center.x, y: center.y - 3),
                 11, .regular, Theme.inkFaint)
            text("⌥ tools   ⇥ mode   esc", at: CGPoint(x: center.x, y: center.y - 30),
                 9, .regular, Theme.inkFaint, tracking: 0.3)
            return
        }

        Theme.glassTint.setFill()
        disc.fill()
        drawRim()

        if items.isEmpty {
            text("no route for", at: CGPoint(x: center.x, y: center.y + 8), 12, .medium, Theme.ink)
            text("this selection", at: CGPoint(x: center.x, y: center.y - 10), 12, .medium, Theme.ink)
        } else {
            for i in items.indices { drawPetal(i) }
        }
        if let errorText { drawToast(errorText) } else { drawHub() }
    }

    /// What sells the glass: a bright arc along the top of the curve fading to a
    /// dark one underneath, so the edge reads as a lit bevel rather than a line.
    /// Drawn as two half-circle strokes rather than a gradient stroke, which
    /// AppKit can't do directly.
    private func drawRim() {
        let inset = discRect.insetBy(dx: 0.75, dy: 0.75)

        for (from, to, colour, width) in [
            (20.0, 160.0, Theme.specular, 1.6),      // lit top
            (200.0, 340.0, Theme.glassEdge, 1.3),    // shaded underside
        ] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: CGPoint(x: inset.midX, y: inset.midY),
                          radius: inset.width / 2, startAngle: from, endAngle: to)
            arc.lineWidth = width
            arc.lineCapStyle = .round
            colour.setStroke()
            arc.stroke()
        }

        // A continuous hairline underneath keeps the circle closed where the two
        // arcs don't meet.
        let ring = NSBezierPath(ovalIn: inset)
        ring.lineWidth = 1
        Theme.hairline.withAlphaComponent(0.10).setStroke()
        ring.stroke()
    }

    private func drawToast(_ message: String) {
        let width: CGFloat = 210
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let str = NSAttributedString(string: message, attributes: [.font: font, .paragraphStyle: para])
        let size = str.boundingRect(with: NSSize(width: width - 20, height: 120),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let box = NSRect(x: center.x - width / 2, y: center.y - (size.height + 20) / 2,
                         width: width, height: size.height + 20)
        let card = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
        Theme.paper.setFill()
        card.fill()
        NSColor.systemRed.withAlphaComponent(0.55).setStroke()
        card.lineWidth = 1
        card.stroke()
        text(message, at: CGPoint(x: box.midX, y: box.midY), 11, .medium, Theme.ink, maxWidth: width - 20)
    }



    private func drawPetal(_ i: Int) {
        let active = (hover ?? focus) == i
        let petal = petalPath(i)
        let fg: NSColor

        if active {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = Theme.accent.withAlphaComponent(0.55)
            glow.shadowBlurRadius = 16
            glow.shadowOffset = .zero
            glow.set()
            Theme.accent.setFill()
            petal.fill()
            NSGraphicsContext.restoreGraphicsState()
            if running { Theme.accent.withAlphaComponent(0.35).setFill(); petal.fill() }
            fg = Theme.onAccent
        } else {
            Theme.petalRest.setFill()
            petal.fill()
            // Each petal gets its own thin lit edge, so the whole wheel looks
            // cut from one sheet of glass rather than printed on the disc.
            Theme.specular.withAlphaComponent(Theme.specular.alphaComponent * 0.45).setStroke()
            petal.lineWidth = 1
            petal.stroke()
            fg = Theme.onPetal
        }

        let item = items[i]
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

        // The centre is the one saturated thing on the wheel. A vertical
        // gradient rather than a flat fill so it reads as a rounded disc.
        NSGradient(starting: Theme.accent, ending: Theme.accentDeep)?
            .draw(in: hub, angle: -90)

        if let thumb {
            NSGraphicsContext.saveGraphicsState()
            hub.addClip()
            thumb.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            text(sourceLabel(), at: CGPoint(x: center.x, y: center.y + 4), 12, .semibold, Theme.onAccent)
        }
        // Nothing else says which mode you're in, and the petals alone are ambiguous.
        if mode != .convert {
            let name = mode == .tools ? "TOOLS" : "RECIPES"
            let colour = thumb == nil ? Theme.onAccent.withAlphaComponent(0.62)
                                      : Theme.paper.withAlphaComponent(0.85)
            text(name, at: CGPoint(x: center.x, y: center.y + hubR - 13), 8.5, .semibold,
                 colour, tracking: 1)
        }
        // Same bevel as the disc, at hub scale.
        let hubArc = NSBezierPath()
        hubArc.appendArc(withCenter: center, radius: hubR - 0.5, startAngle: 25, endAngle: 155)
        hubArc.lineWidth = 1.2
        hubArc.lineCapStyle = .round
        Theme.specular.setStroke()
        hubArc.stroke()
        Theme.hairline.withAlphaComponent(0.14).setStroke()
        hub.lineWidth = 1
        hub.stroke()

        let pill = running ? "\(Int(progress * 100))%"
            : presetParent.map { $0.label.uppercased() } ?? (focusTitle() ?? "")
        guard !pill.isEmpty else { return }
        let width = (pill as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width + 18
        let r = NSRect(x: center.x - width / 2, y: center.y - hubR + 6, width: width, height: 20)
        let shape = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        glow.shadowBlurRadius = 10
        glow.shadowOffset = .zero
        glow.set()
        // The pill overlaps the yellow centre, so it can't also be yellow.
        Theme.onAccent.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        text(pill, at: CGPoint(x: r.midX, y: r.midY), 11, .semibold, Theme.accent)
    }

    private func sourceLabel() -> String {
        if folderInput != nil { return "\(inputs.count) IN FOLDER" }
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
        let p = convert(e.locationInWindow, from: nil)
        if inputs.isEmpty {
            // The whole empty ring is one target, so say so with the cursor and
            // by warming the dashed edge.
            let inside = hypot(p.x - center.x, p.y - center.y) <= discR
            (inside ? NSCursor.pointingHand : NSCursor.arrow).set()
            if inside != hoveringEmpty { hoveringEmpty = inside; needsDisplay = true }
            return
        }
        if hoveringEmpty { hoveringEmpty = false }
        let i = petalIndex(at: p)
        if i != hover { hover = i; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) {
        NSCursor.arrow.set()
        if hover != nil || hoveringEmpty { hover = nil; hoveringEmpty = false; needsDisplay = true }
    }

    override func mouseDown(with e: NSEvent) {
        guard !running else { return }
        let p = convert(e.locationInWindow, from: nil)
        if inputs.isEmpty {
            if hypot(p.x - center.x, p.y - center.y) <= discR { chooseFiles() }
            return
        }
        guard let i = petalIndex(at: p) else { return }
        focus = i
        items[i].run()
    }

    /// The empty ring doubles as a button. Dragging is the fast path, but a
    /// click here opens Finder's own picker — the same wheel either way.
    func chooseFiles() {
        // A drag-summoned panel is on a dismiss timer and isn't key; the picker
        // needs both of those undone or it opens behind and then vanishes.
        owner?.cancelDragDismiss()
        dragSummoned = false
        owner?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true      // folders are an input too (→ zip)
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Choose"
        panel.message = "Pick a file to convert."
        // Free-standing rather than a sheet: the wheel is a borderless 300pt
        // panel and a sheet hanging off it would be wider than its own parent.
        // It also has to clear the wheel's floating level to be visible at all.
        panel.level = .modalPanel
        panel.begin { [weak self] response in
            guard let self else { return }
            self.owner?.makeKeyAndOrderFront(nil)
            self.owner?.makeFirstResponder(self)
            guard response == .OK, !panel.urls.isEmpty else { return }
            self.accept(panel.urls)
        }
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53:                                 // esc
            if presetParent != nil { presetParent = nil; rebuild() } else { owner?.orderOut(nil) }
        case 123, 126: step(-1)                   // ← ↑
        case 124, 125: step(+1)                   // → ↓
        case 36, 76, 49:                         // return, space
            if running { return }
            if inputs.isEmpty { chooseFiles() }
            else if items.indices.contains(focus) { items[focus].run() }
        case 48: cycleMode()                     // tab
        default:
            let key = e.charactersIgnoringModifiers
            if e.modifierFlags.contains(.command), key == "v" { paste() }
            else if e.modifierFlags.contains(.command), key == "o" { chooseFiles() }
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

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        loadFromDrag(s)
        return .copy
    }

    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        if inputs.isEmpty { loadFromDrag(s) }
        let i = petalIndex(at: convert(s.draggingLocation, from: nil))
        if i != hover { hover = i; needsDisplay = true }
        return .copy
    }

    /// The drag pasteboard is readable now that the drag is over our window —
    /// which it wasn't from `DragMonitor`.
    private func loadFromDrag(_ s: NSDraggingInfo) {
        guard let urls = Self.fileURLs(s.draggingPasteboard), !urls.isEmpty else { return }
        owner?.cancelDragDismiss()
        accept(urls)
    }

    override func draggingExited(_ s: NSDraggingInfo?) {
        if hover != nil { hover = nil; needsDisplay = true }
    }

    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let urls = Self.fileURLs(s.draggingPasteboard), !urls.isEmpty else { return false }
        owner?.cancelDragDismiss()
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
