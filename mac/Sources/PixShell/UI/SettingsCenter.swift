import AppKit

/// 单窗口设置中心。
///
/// 功能边界：
/// - 本文件负责设置窗口、左侧分类导航、主题刷新，以及各设置页的装载/切换。
/// - 代理、密钥、主机指纹、AI、备份仍由各自 Manager/Panel 负责业务逻辑；这里只复用其内容视图。
/// - 离开内嵌页时必须把内容视图归还原控制器，避免独立窗口再次打开时内容消失。
final class SettingsCenter: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private struct Item {
        let title: String
        let page: String?
        let indent: Int
    }

    private weak var app: AppDelegate?
    private let root = NSView()
    private let sidebar = NSScrollView()
    private let table = NSTableView()
    private let content = NSView()
    private var restoreEmbeddedView: (() -> Void)?
    private let items: [Item] = [
        .init(title: "常规", page: "general", indent: 0),
        .init(title: "终端", page: nil, indent: 0),
        .init(title: "外观与行为", page: "terminal", indent: 1),
        .init(title: "连接与安全", page: nil, indent: 0),
        .init(title: "代理服务器", page: "proxy", indent: 1),
        .init(title: "密钥管理", page: "keys", indent: 1),
        .init(title: "主机指纹", page: "fingerprints", indent: 1),
        .init(title: "集成与维护", page: nil, indent: 0),
        .init(title: "AI 对接", page: "ai", indent: 1),
        .init(title: "备份与 WebDAV", page: "backup", indent: 1),
        .init(title: "软件更新", page: "update", indent: 1),
    ]

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "设置"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.bg
        window.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PixShell-Settings-v1")
        super.init(window: window)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshTheme(reloadPage: false)
        window?.center(onScreenOf: app?.window)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if table.selectedRow < 0 { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        showPage(items[max(0, table.selectedRow)].page ?? "general")
    }

    private func build() {
        guard let window else { return }
        root.wantsLayer = true; root.layer?.backgroundColor = Theme.bg.cgColor
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(split)

        sidebar.drawsBackground = true; sidebar.backgroundColor = Theme.side
        sidebar.hasVerticalScroller = true
        let column = NSTableColumn(identifier: .init("settings")); column.width = 220
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 30
        table.backgroundColor = Theme.side; table.selectionHighlightStyle = .regular
        table.dataSource = self; table.delegate = self
        sidebar.documentView = table

        content.wantsLayer = true; content.layer?.backgroundColor = Theme.bg.cgColor
        split.addArrangedSubview(sidebar); split.addArrangedSubview(content)
        sidebar.widthAnchor.constraint(equalToConstant: 230).isActive = true
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: root.topAnchor), split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        window.contentView = root
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.title)
        label.font = Theme.ui(item.indent == 0 ? 13 : 12, item.indent == 0 ? .semibold : .regular)
        label.textColor = item.page == nil ? Theme.muted : Theme.text
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: item.indent == 0 ? 12 : 32),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
        ])
        return cell
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { items[row].page != nil }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, let page = items[table.selectedRow].page else { return }
        showPage(page)
    }

    private func clearPage() {
        // 页面切换前先归还借用的 Manager 内容视图，再清理当前容器。
        restoreEmbeddedView?(); restoreEmbeddedView = nil
        content.subviews.forEach { $0.removeFromSuperview() }
    }
    private func install(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor), view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor), view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
    }
    private func showPage(_ id: String) {
        clearPage()
        guard let app else { return }
        switch id {
        case "general": install(generalPage(app))
        case "terminal": install(terminalPage(app))
        case "proxy":
            let panel = ProxyPanel(frame: .zero); panel.onClose = { [weak self] in self?.select("general") }
            panel.showEmbedded(); install(panel)
        case "keys": embed(app.keyManager.embeddedView(), restore: { [weak app] view in app?.keyManager.window?.contentView = view }, close: { [weak self] in self?.select("general") }, owner: app.keyManager)
        case "fingerprints": embed(app.fingerprintManager.embeddedView(), restore: { [weak app] view in app?.fingerprintManager.window?.contentView = view }, close: { [weak self] in self?.select("general") }, owner: app.fingerprintManager)
        case "ai": embed(app.aiSshBridgeManager.embeddedView(), restore: { [weak app] view in app?.aiSshBridgeManager.window?.contentView = view }, close: { [weak self] in self?.select("general") }, owner: app.aiSshBridgeManager)
        case "backup": embed(app.backupPanel.embeddedView(enabled: app.backupEnabled), restore: { [weak app] view in app?.backupPanel.window?.contentView = view }, close: { [weak self] in self?.select("general") }, owner: app.backupPanel)
        case "update": install(updatePage(app))
        default: install(generalPage(app))
        }
    }

    private func embed(_ view: NSView, restore: @escaping (NSView) -> Void, close: @escaping () -> Void, owner: AnyObject) {
        // Manager 原有窗口继续保留；设置中心只在当前页面显示期间临时托管 contentView。
        if let manager = owner as? KeyManager { manager.onClose = close }
        if let manager = owner as? FingerprintManager { manager.onClose = close }
        if let manager = owner as? AiSshBridgeManager { manager.onClose = close }
        if let manager = owner as? BackupPanel { manager.onClose = close }
        restoreEmbeddedView = { [weak view] in if let view { view.removeFromSuperview(); restore(view) } }
        install(view)
    }

    private func select(_ page: String) {
        guard let row = items.firstIndex(where: { $0.page == page }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func page(title: String, views: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title); titleLabel.font = Theme.ui(20, .semibold); titleLabel.textColor = Theme.text
        let stack = NSStackView(views: [titleLabel] + views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView(); root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -30),
        ])
        return root
    }

    private func generalPage(_ app: AppDelegate) -> NSView {
        let theme = NSPopUpButton(); let kinds: [Theme.Kind] = [.dark, .light, .ink, .retro]
        theme.addItems(withTitles: kinds.map(\.display)); theme.selectItem(at: kinds.firstIndex(of: Theme.kind) ?? 0); theme.tag = 101
        let highlight = NSButton(checkboxWithTitle: "终端语义高亮", target: nil, action: nil); highlight.state = app.highlightEnabled ? .on : .off; highlight.tag = 102
        let save = PillButton("应用", style: .primary, hPad: 14, target: self, action: #selector(saveGeneral(_:)))
        let grid = NSGridView(views: [[NSTextField(labelWithString: "主题"), theme], [NSTextField(labelWithString: ""), highlight]])
        grid.rowSpacing = 12; grid.columnSpacing = 16
        return page(title: "常规", views: [grid, save])
    }

    private func terminalPage(_ app: AppDelegate) -> NSView {
        let scheme = NSPopUpButton(); scheme.addItem(withTitle: "跟随主题")
        TermSchemes.all.forEach { scheme.addItem(withTitle: $0.name) }
        scheme.selectItem(at: TermSchemes.all.firstIndex(where: { $0.id == TermTheme.schemeId }).map { $0 + 1 } ?? 0); scheme.tag = 201
        let font = NSTextField(string: String(Int(app.currentFontSize()))); font.tag = 202
        let history = NSTextField(string: String(app.cmdPanel?.parameterHistoryLimit ?? 50)); history.tag = 203
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "终端配色"), scheme], [NSTextField(labelWithString: "字体大小"), font],
            [NSTextField(labelWithString: "参数历史数量"), history],
        ])
        grid.rowSpacing = 12; grid.columnSpacing = 16
        let save = PillButton("应用", style: .primary, hPad: 14, target: self, action: #selector(saveTerminal(_:)))
        return page(title: "终端 · 外观与行为", views: [grid, save])
    }

    private func updatePage(_ app: AppDelegate) -> NSView {
        let info = NSTextField(wrappingLabelWithString: "检查 GitHub Releases 中是否存在新版本。")
        info.textColor = Theme.muted; info.font = Theme.ui(12)
        let button = PillButton("检查更新", style: .primary, hPad: 14, target: app, action: #selector(AppDelegate.checkUpdate))
        return page(title: "软件更新", views: [info, button])
    }

    @objc private func saveGeneral(_ sender: NSButton) {
        guard let app, let root = sender.superview else { return }
        let theme = find(tag: 101, in: root) as? NSPopUpButton
        let highlight = find(tag: 102, in: root) as? NSButton
        app.highlightEnabled = highlight?.state == .on
        let kinds: [Theme.Kind] = [.dark, .light, .ink, .retro]
        if let theme { let kind = kinds[max(0, theme.indexOfSelectedItem)]; if kind != .dark { Theme.lightKind = kind }; if kind != Theme.kind { app.applyThemeKind(kind); refreshTheme() } }
        app.setStatus("设置已保存")
    }

    private func refreshTheme(reloadPage: Bool = true) {
        // AppKit 的自定义 layer 颜色不会随 appearance 自动刷新，需同步更新窗口、侧栏和内容区。
        window?.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
        window?.backgroundColor = Theme.bg
        root.layer?.backgroundColor = Theme.bg.cgColor
        content.layer?.backgroundColor = Theme.bg.cgColor
        sidebar.backgroundColor = Theme.side
        table.backgroundColor = Theme.side
        table.reloadData()
        if reloadPage, table.selectedRow >= 0, let page = items[table.selectedRow].page { showPage(page) }
    }
    @objc private func saveTerminal(_ sender: NSButton) {
        guard let app, let root = sender.superview else { return }
        if let scheme = find(tag: 201, in: root) as? NSPopUpButton {
            TermTheme.schemeId = scheme.indexOfSelectedItem <= 0 ? "" : TermSchemes.all[scheme.indexOfSelectedItem - 1].id
        }
        if let field = find(tag: 202, in: root) as? NSTextField, let value = Double(field.stringValue) { app.setFontSize(CGFloat(max(9, min(24, value)))) }
        if let field = find(tag: 203, in: root) as? NSTextField, let value = Int(field.stringValue) { app.cmdPanel?.setParameterHistoryLimit(value) }
        for session in app.sessions { TermTheme.apply(to: session.termView, dark: Theme.dark) }
        app.setStatus("终端设置已保存")
    }
    private func find(tag: Int, in view: NSView) -> NSView? {
        if view.tag == tag { return view }
        for child in view.subviews { if let found = find(tag: tag, in: child) { return found } }
        return nil
    }
}
