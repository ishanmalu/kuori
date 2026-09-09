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
            guard !summoning,
                  NSEvent.modifierFlags.contains(.shift),
                  let urls = draggedFiles() else { return }
            summoning = true
            DropPanel.shared.beginDrop(urls: urls, at: NSEvent.mouseLocation)

        case .leftMouseUp:
            guard summoning else { return }
            summoning = false
            // If the drop never reached the window, tidy up after AppKit has had its turn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                DropPanel.shared.dismissIfDragSummoned()
            }

        default:
            break
        }
    }

    private func draggedFiles() -> [URL]? {
        let pb = NSPasteboard(name: .drag)
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return nil }
        return urls
    }
}
