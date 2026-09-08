import AppKit

/// Minimal settings: login toggle, watch-folder table (add / remove / enable),
/// and shortcuts to the JSON that backs presets and recipes.
final class SettingsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = SettingsWindow()

    private let table = NSTableView()
    private let loginCheck = NSButton(checkboxWithTitle: "Open Kuori at login", target: nil, action: nil)

    private convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Kuori Settings"
        self.init(window: win)
        build()
    }

    func show() {
        WatchFolders.shared.load()
        loginCheck.state = LoginItem.isEnabled ? .on : .off
        table.reloadData()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        guard let content = window?.contentView else { return }
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin)

        let watchLabel = NSTextField(labelWithString: "Watch folders")
        watchLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        table.usesAlternatingRowBackgroundColors = true
        for (id, title, w) in [("on", "", 26), ("folder", "Folder", 260), ("action", "Action", 140)] {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title; c.width = CGFloat(w)
            table.addTableColumn(c)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let addBtn = NSButton(title: "Add…", target: self, action: #selector(addFolder))
        let rmBtn = NSButton(title: "Remove", target: self, action: #selector(removeFolder))
        let presetsBtn = NSButton(title: "Edit presets.json", target: self, action: #selector(revealPresets))
        let recipesBtn = NSButton(title: "Edit recipes.json", target: self, action: #selector(revealRecipes))
        [addBtn, rmBtn, presetsBtn, recipesBtn].forEach { $0.bezelStyle = .rounded }

        let btnRow = NSStackView(views: [addBtn, rmBtn, NSView(), presetsBtn, recipesBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let stack = NSStackView(views: [loginCheck, watchLabel, scroll, btnRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            scroll.heightAnchor.constraint(equalToConstant: 210),
            btnRow.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    @objc private func toggleLogin() { _ = LoginItem.toggle(); loginCheck.state = LoginItem.isEnabled ? .on : .off }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Watch"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        let fmt = NSAlert()
        fmt.messageText = "Convert new files in \(dir.lastPathComponent) to:"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        popup.addItems(withTitles: ["webp", "jpg", "png", "pdf", "mp4", "mp3"] + Recipes.all().map { "recipe: \($0.name)" })
        fmt.accessoryView = popup
        fmt.addButton(withTitle: "Add"); fmt.addButton(withTitle: "Cancel")
        guard fmt.runModal() == .alertFirstButtonReturn else { return }

        let choice = popup.titleOfSelectedItem ?? "webp"
        var rule = WatchRule(folder: dir.path)
        if choice.hasPrefix("recipe: ") { rule.recipe = String(choice.dropFirst(8)) } else { rule.toFormat = choice }
        WatchFolders.shared.add(rule)
        table.reloadData()
    }

    @objc private func removeFolder() {
        let r = table.selectedRow
        guard r >= 0 else { return }
        WatchFolders.shared.remove(at: r)
        table.reloadData()
    }

    @objc private func revealPresets() { Presets.seedFileIfMissing(); NSWorkspace.shared.open(Support.file("presets.json")) }
    @objc private func revealRecipes() { Recipes.seedFileIfMissing(); NSWorkspace.shared.open(Support.file("recipes.json")) }

    // table

    func numberOfRows(in tableView: NSTableView) -> Int { WatchFolders.shared.rules.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let rule = WatchFolders.shared.rules[row]
        switch col?.identifier.rawValue {
        case "on":
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            b.state = rule.enabled ? .on : .off
            b.tag = row
            return b
        case "folder":
            return NSTextField(labelWithString: (rule.folder as NSString).abbreviatingWithTildeInPath)
        default:
            return NSTextField(labelWithString: rule.recipe.map { "recipe \($0)" } ?? "→ \((rule.toFormat ?? "?").uppercased())")
        }
    }

    @objc private func toggleRow(_ sender: NSButton) {
        WatchFolders.shared.setEnabled(sender.state == .on, at: sender.tag)
    }
}
