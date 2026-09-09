import AppKit

/// Watches for a Shift-held file drag anywhere on screen and pops the wheel
/// under the cursor, the way Tangerine does. Mouse-event monitors don't need
/// Accessibility (only keyboard ones do), so this works out of the box.
final class DragMonitor {
    static let shared = DragMonitor()

    private var handles: [Any] = []
    private var summoning = false

    func start() {
        guard handles.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            handles.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) {
            handles.append(l)
        }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDragged:
            // A background process can't read the drag pasteboard, so we can't
            // tell yet whether files are being dragged. Show the wheel under the
            // cursor; it reads the drag once it enters the window, and dismisses
            // itself if nothing does.
            guard !summoning, NSEvent.modifierFlags.contains(.shift) else { return }
            summoning = true
            DispatchQueue.main.async { DropPanel.shared.beginDrop(at: NSEvent.mouseLocation) }

        case .leftMouseUp:
            guard summoning else { return }
            summoning = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                DropPanel.shared.dismissIfDragSummoned()
            }

        default:
            break
        }
    }
}
