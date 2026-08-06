import AppKit

/// 命令板（底部坞「命令」tab）。**布局照老仓库来，左右分栏**：
///
///   [📁默认分类 📁防火墙 📁系统 …(排满换行)]                        [＋新建]
///   ┌──────────────────────────────┬─┬─────────────────────────┐
///   │ 命令列表（带边框/换行/可滚动）  │ │ 命令编辑器        ⟩收起 │
///   │  名称⚙  名称⚙  名称⚙ …        │ │ ┌─────────────────────┐ │
///   ├──────────────────────────────┤ │ │ 多行文本            │ │
///   │ 发送到 [当前会话▾] [发送]      │ │ └─────────────────────┘ │
///   └──────────────────────────────┘ │ 发送到 [当前会话▾] [发送]│
///                                    └─────────────────────────┘
///
/// 之前做成了"分类 pill 一行 + 命令 chips 横向滚动一行 + 编辑器压在下面"，
/// 命令被裁掉半截根本点不到，用户反馈"完全不可用"。要点：
///  1. 分类是**文件夹样式**且**换行**（FlowView），不是单行 pill；
///  2. 命令列表在**带边框的盒子**里换行铺开，每条右边一个 ⚙（编辑/删除）；
///  3. 编辑器在**右栏**（不是压在下面），可收起成窄条；
///  4. 左右各有自己的 `发送到 + 发送`：左边发列表选中项，右边发编辑器内容。
final class CommandPanel: NSView, NSTextViewDelegate {
    private let store = QuickCommandStore()
    private let groupFlow = FlowView()          // 分类文件夹（换行）
    private let cmdFlow = FlowView()            // 命令列表（换行）
    private let edTargetPopup = NSPopUpButton()     // 发送到目标选择
    var editor: NSTextView!
    private var editorScroll: NSScrollView!
    private var rightCol: NSView!
    private var rightWidthC: NSLayoutConstraint!
    private var resizeStartRightWidth: CGFloat = 0
    private var collapseBtn: PillButton!
    private var editorParts: [NSView] = []      // 展开态显示的三块（头/编辑器/发送条）
    private var expandStrip: PillButton!        // 收起态占满窄条的展开按钮
    private var editorCollapsed = false
    private var selectedGroup: String?
    private var selectedCmdId: String?          // 列表里被选中的那条（左栏「发送」用）
    private let paramBox = CardView(radius: Theme.radiusSm, bg: Theme.bg2, border: Theme.border)
    private let paramFields = NSStackView()
    private let paramTargetPopup = NSPopUpButton()
    // 选中命令名称使用实色标签，和旧版命令详情的左上角标识保持一致。
    private let detailName = PillButton("请选择命令", style: .primary, hPad: 7, height: 22,
                                        font: Theme.ui(11, .semibold))
    private let detailCommand = NSTextField(labelWithString: "")
    private var paramHeightC: NSLayoutConstraint!
    private var paramFieldsWidthC: NSLayoutConstraint!
    private var paramInputs: [String: NSComboBox] = [:]
    private var pendingTemplate: String?
    private var pendingAutoReturn = true
    private static let paramHistoryKey = "pixshell.quickCommand.paramHistory"
    private static let paramHistoryLimitKey = "pixshell.quickCommand.paramHistoryLimit"
    private var didSelectInitialGroup = false
    var parameterHistoryLimit: Int {
        let saved = UserDefaults.standard.integer(forKey: Self.paramHistoryLimitKey)
        return saved == 0 ? 50 : min(500, max(1, saved))
    }

    /// 右栏展开宽度；收起后只留一个窄条。
    /// 截图 P0：命令 tab 打开时编辑器被默认收/窄到看不见 —— 默认展开且更宽一点。
    private static let rightExpanded: CGFloat = 280
    private static let rightCollapsed: CGFloat = 30
    private static let rightWidthKey = "pixshell.commandPanel.editorWidth"

    /// 发送回调：(命令文本, 目标)。文本已含换行。
    var onSendTo: ((String, SendTarget) -> Void)?
    var onShowHistory: ((NSView) -> Void)?
    /// 使用当前 SSH 会话补全编辑器末尾的命令名或远端路径。
    var onCompleteEditor: ((String, @escaping ([(title: String, value: String)]) -> Void) -> Void)?
    private var completionPopover: NSPopover?
    /// 目标下拉数据源：已连接会话标题
    var sessionsProvider: (() -> [(title: String, connected: Bool)])?

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); build(); reload() }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: 布局
    private func build() {
        wantsLayer = true; layer?.backgroundColor = Theme.bg.cgColor

        // ── 顶部：分类文件夹（换行）+ 新建 ──
        let addBtn = PillButton("＋ 新建", style: .secondary, hPad: 10, height: 22,
                                target: self, action: #selector(newCommand))
        addBtn.setContentHuggingPriority(.required, for: .horizontal)

        // ── 左栏：命令列表（带边框盒子 + 换行 + 可滚动）──
        let listBox = CardView(radius: Theme.radiusSm, bg: Theme.bg2, border: Theme.border)
        let listScroll = OverlayScrollView()
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.hasHorizontalScroller = false
        listScroll.autohidesScrollers = true
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        let listDoc = FlippedView(); listDoc.translatesAutoresizingMaskIntoConstraints = false
        cmdFlow.inset = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        cmdFlow.hGap = 4
        listDoc.addSubview(cmdFlow)
        listScroll.documentView = listDoc
        listBox.addSubview(listScroll)
        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: listBox.topAnchor, constant: 1),
            listScroll.leadingAnchor.constraint(equalTo: listBox.leadingAnchor, constant: 1),
            listScroll.trailingAnchor.constraint(equalTo: listBox.trailingAnchor, constant: -1),
            listScroll.bottomAnchor.constraint(equalTo: listBox.bottomAnchor, constant: -1),
            listDoc.topAnchor.constraint(equalTo: listScroll.topAnchor),
            listDoc.leadingAnchor.constraint(equalTo: listScroll.leadingAnchor),
            listDoc.widthAnchor.constraint(equalTo: listScroll.widthAnchor),
            cmdFlow.topAnchor.constraint(equalTo: listDoc.topAnchor),
            cmdFlow.leadingAnchor.constraint(equalTo: listDoc.leadingAnchor),
            cmdFlow.trailingAnchor.constraint(equalTo: listDoc.trailingAnchor),
            listDoc.bottomAnchor.constraint(equalTo: cmdFlow.bottomAnchor),
        ])

        let leftCol = NSView(); leftCol.translatesAutoresizingMaskIntoConstraints = false
        leftCol.addSubview(listBox)
        NSLayoutConstraint.activate([
            listBox.topAnchor.constraint(equalTo: leftCol.topAnchor),
            listBox.leadingAnchor.constraint(equalTo: leftCol.leadingAnchor),
            listBox.trailingAnchor.constraint(equalTo: leftCol.trailingAnchor),
            listBox.bottomAnchor.constraint(equalTo: leftCol.bottomAnchor),
        ])

        // ── 右栏：命令编辑器（可收起）──
        collapseBtn = PillButton(L10n.t("cmd.collapse"), style: .ghost, hPad: 8, height: 20,
                                 target: self, action: #selector(toggleEditor))
        let edLabel = NSTextField(labelWithString: "命令编辑器")
        edLabel.font = Theme.ui(11, .medium); edLabel.textColor = Theme.muted
        let optBtnTop = PillButton(L10n.t("cmd.options"), style: .ghost, hPad: 8, height: 20,
                                   font: Theme.ui(11), target: self, action: #selector(editorOptions))
        let edHead = NSStackView(views: [edLabel, NSView(), optBtnTop, collapseBtn])
        edHead.spacing = 8; edHead.alignment = .centerY
        edHead.translatesAutoresizingMaskIntoConstraints = false

        (editorScroll, editor) = ScrollableText.make(font: Theme.mono(12), editable: true,
                                                     bg: Theme.bg2, border: Theme.border)
        editor.delegate = self

        edTargetPopup.font = Theme.ui(11)
        edTargetPopup.translatesAutoresizingMaskIntoConstraints = false
        edTargetPopup.setContentHuggingPriority(.required, for: .horizontal)
        edTargetPopup.setContentCompressionResistancePriority(.required, for: .horizontal)
        let edSendLab = small("发送到")
        let edHist = PillButton(L10n.t("cmd.history"), style: .secondary, hPad: 12, height: 24, target: self, action: #selector(showHistory))
        let edSend = PillButton("发送", style: .primary, hPad: 14, height: 24,
                                target: self, action: #selector(sendEditor))
        let edSendBar = NSStackView(views: [NSView(), edHist, edSendLab, edTargetPopup, edSend])
        edSendBar.spacing = 6; edSendBar.alignment = .centerY
        edSendBar.translatesAutoresizingMaskIntoConstraints = false

        // 收起态：占满窄栏的展开按钮（竖着的「‹ 编辑器」）
        expandStrip = PillButton("‹", style: .secondary, hPad: 2, height: 24,
                                 font: Theme.ui(11, .semibold), target: self, action: #selector(expandEditor))
        expandStrip.toolTip = L10n.t("cmd.expand")
        expandStrip.isHidden = true
        expandStrip.translatesAutoresizingMaskIntoConstraints = false

        rightCol = NSView(); rightCol.translatesAutoresizingMaskIntoConstraints = false
        rightCol.addSubview(edHead); rightCol.addSubview(editorScroll); rightCol.addSubview(edSendBar)
        rightCol.addSubview(expandStrip)
        editorParts = [edHead, editorScroll, edSendBar]
        NSLayoutConstraint.activate([
            expandStrip.topAnchor.constraint(equalTo: rightCol.topAnchor),
            expandStrip.leadingAnchor.constraint(equalTo: rightCol.leadingAnchor),
            expandStrip.trailingAnchor.constraint(equalTo: rightCol.trailingAnchor),
            edHead.topAnchor.constraint(equalTo: rightCol.topAnchor),
            edHead.leadingAnchor.constraint(equalTo: rightCol.leadingAnchor),
            edHead.trailingAnchor.constraint(equalTo: rightCol.trailingAnchor),
            editorScroll.topAnchor.constraint(equalTo: edHead.bottomAnchor, constant: 4),
            editorScroll.leadingAnchor.constraint(equalTo: rightCol.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: rightCol.trailingAnchor),
            edSendBar.topAnchor.constraint(equalTo: editorScroll.bottomAnchor, constant: 6),
            edSendBar.leadingAnchor.constraint(equalTo: rightCol.leadingAnchor),
            edSendBar.trailingAnchor.constraint(equalTo: rightCol.trailingAnchor),
            edSendBar.bottomAnchor.constraint(equalTo: rightCol.bottomAnchor),
        ])

        // ── 参数填写区：固定在命令窗口下方，不再逐个弹 NSAlert ──
        paramFields.orientation = .horizontal
        paramFields.alignment = .centerY
        paramFields.spacing = 10
        paramFields.translatesAutoresizingMaskIntoConstraints = false
        // 参数数量不确定，单独使用横向滚动区域；右侧发送操作不参与滚动，也不会被挤走。
        let paramScroll = NSScrollView()
        paramScroll.drawsBackground = false
        paramScroll.hasVerticalScroller = false
        paramScroll.hasHorizontalScroller = true
        paramScroll.autohidesScrollers = true
        paramScroll.scrollerStyle = .overlay
        paramScroll.translatesAutoresizingMaskIntoConstraints = false
        let paramDoc = FlippedView()
        paramDoc.translatesAutoresizingMaskIntoConstraints = false
        paramDoc.addSubview(paramFields)
        paramScroll.documentView = paramDoc
        NSLayoutConstraint.activate([
            paramDoc.leadingAnchor.constraint(equalTo: paramScroll.contentView.leadingAnchor),
            paramDoc.topAnchor.constraint(equalTo: paramScroll.contentView.topAnchor),
            paramDoc.heightAnchor.constraint(equalTo: paramScroll.contentView.heightAnchor),
            paramDoc.widthAnchor.constraint(greaterThanOrEqualTo: paramScroll.contentView.widthAnchor),
            paramFields.leadingAnchor.constraint(equalTo: paramDoc.leadingAnchor),
            paramFields.trailingAnchor.constraint(lessThanOrEqualTo: paramDoc.trailingAnchor),
            paramFields.centerYAnchor.constraint(equalTo: paramDoc.centerYAnchor),
        ])
        // 内容较少时文档铺满可视区，但参数栈保持固有宽度；内容较多时文档随参数扩展并可滚动。
        let paramDocFitsContent = paramDoc.widthAnchor.constraint(equalTo: paramFields.widthAnchor)
        paramDocFitsContent.priority = .defaultHigh
        paramDocFitsContent.isActive = true
        paramFields.distribution = .fill
        paramFields.setContentHuggingPriority(.required, for: .horizontal)
        paramFields.setContentCompressionResistancePriority(.required, for: .horizontal)
        // 明确使用参数内容的实际总宽度，防止 NSStackView 把剩余空间分散成巨大间距。
        paramFieldsWidthC = paramFields.widthAnchor.constraint(equalToConstant: 0)
        paramFieldsWidthC.isActive = true
        detailCommand.font = Theme.mono(11); detailCommand.textColor = Theme.text
        detailCommand.lineBreakMode = .byTruncatingTail
        detailCommand.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let editDetail = PillButton("编辑", style: .secondary, hPad: 10, height: 24,
                                    target: self, action: #selector(editSelectedCommand))
        let detailHeader = NSStackView(views: [detailName, detailCommand, NSView(), editDetail])
        detailHeader.orientation = .horizontal; detailHeader.alignment = .centerY; detailHeader.spacing = 10
        detailHeader.translatesAutoresizingMaskIntoConstraints = false
        paramTargetPopup.font = Theme.ui(11)
        paramTargetPopup.addItems(withTitles: [L10n.t("cmd.current"), L10n.t("cmd.allConnected")])
        paramTargetPopup.translatesAutoresizingMaskIntoConstraints = false
        // 使用控件的文字固有宽度，不为下拉框保留多余的左右空白。
        paramTargetPopup.setContentHuggingPriority(.required, for: .horizontal)
        paramTargetPopup.setContentCompressionResistancePriority(.required, for: .horizontal)
        let targetLabel = small("发送到")
        let sendParams = PillButton("发送", style: .primary, hPad: 14, height: 24,
                                    target: self, action: #selector(confirmParamsAction))
        // 紧凑详情区：参数和发送操作共用第二行，给上方命令列表留出尽可能多的高度。
        let paramActions = NSStackView(views: [targetLabel, paramTargetPopup, sendParams])
        paramActions.orientation = .horizontal; paramActions.alignment = .centerY
        paramActions.spacing = 6; paramActions.distribution = .fill
        paramActions.translatesAutoresizingMaskIntoConstraints = false
        let detailLowerRow = NSStackView(views: [paramScroll, paramActions])
        detailLowerRow.orientation = .horizontal; detailLowerRow.alignment = .centerY
        detailLowerRow.spacing = 8; detailLowerRow.translatesAutoresizingMaskIntoConstraints = false
        paramScroll.heightAnchor.constraint(equalToConstant: 26).isActive = true
        paramScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        paramActions.setContentHuggingPriority(.required, for: .horizontal)
        paramActions.setContentCompressionResistancePriority(.required, for: .horizontal)
        paramBox.addSubview(detailHeader); paramBox.addSubview(detailLowerRow)
        paramBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            detailHeader.topAnchor.constraint(equalTo: paramBox.topAnchor, constant: 5),
            detailHeader.leadingAnchor.constraint(equalTo: paramBox.leadingAnchor, constant: 8),
            detailHeader.trailingAnchor.constraint(equalTo: paramBox.trailingAnchor, constant: -8),
            detailLowerRow.topAnchor.constraint(equalTo: detailHeader.bottomAnchor, constant: 3),
            detailLowerRow.leadingAnchor.constraint(equalTo: paramBox.leadingAnchor, constant: 8),
            detailLowerRow.trailingAnchor.constraint(equalTo: paramBox.trailingAnchor, constant: -8),
            detailLowerRow.bottomAnchor.constraint(equalTo: paramBox.bottomAnchor, constant: -5),
        ])
        paramHeightC = paramBox.heightAnchor.constraint(equalToConstant: 0)
        paramHeightC.isActive = true
        paramHeightC.constant = 58
        paramBox.isHidden = false

        // ── 组装：顶部分类行 + [左栏 | 竖分隔 | 右栏] + 参数区 ──
        let divider = DividerView()
        divider.wantsLayer = true; divider.layer?.backgroundColor = .clear
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.toolTip = "拖动调整命令列表与命令编辑器宽度"
        let dividerLine = NSView()
        dividerLine.wantsLayer = true; dividerLine.layer?.backgroundColor = Theme.border.cgColor
        dividerLine.translatesAutoresizingMaskIntoConstraints = false
        divider.addSubview(dividerLine)
        NSLayoutConstraint.activate([
            dividerLine.centerXAnchor.constraint(equalTo: divider.centerXAnchor),
            dividerLine.topAnchor.constraint(equalTo: divider.topAnchor),
            dividerLine.bottomAnchor.constraint(equalTo: divider.bottomAnchor),
            dividerLine.widthAnchor.constraint(equalToConstant: 1),
        ])
        divider.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(resizeColumns(_:))))

        addSubview(groupFlow); addSubview(addBtn)
        addSubview(leftCol); addSubview(divider); addSubview(rightCol); addSubview(paramBox)

        let savedEditorWidth = UserDefaults.standard.double(forKey: Self.rightWidthKey)
        rightWidthC = rightCol.widthAnchor.constraint(equalToConstant:
            savedEditorWidth > 0 ? CGFloat(savedEditorWidth) : Self.rightExpanded)
        NSLayoutConstraint.activate([
            groupFlow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            groupFlow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            groupFlow.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -8),
            addBtn.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            leftCol.topAnchor.constraint(equalTo: groupFlow.bottomAnchor, constant: 8),
            leftCol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftCol.bottomAnchor.constraint(equalTo: paramBox.topAnchor, constant: -6),

            divider.leadingAnchor.constraint(equalTo: leftCol.trailingAnchor, constant: 8),
            divider.widthAnchor.constraint(equalToConstant: 7),
            divider.topAnchor.constraint(equalTo: leftCol.topAnchor),
            divider.bottomAnchor.constraint(equalTo: rightCol.bottomAnchor),

            rightCol.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 8),
            rightCol.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightCol.topAnchor.constraint(equalTo: leftCol.topAnchor),
            rightCol.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            rightWidthC,
            // 参数表单属于命令列表，只占左列；右侧编辑器保持完整高度。
            paramBox.leadingAnchor.constraint(equalTo: leftCol.leadingAnchor),
            paramBox.trailingAnchor.constraint(equalTo: leftCol.trailingAnchor),
            paramBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    private func small(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t); l.font = Theme.ui(11); l.textColor = Theme.muted
        return l
    }

    // MARK: 数据
    func reload() {
        reloadTargets()
        reloadGroups()
        reloadChips()
    }

    func applySyncedCommands(_ commands: [QuickCommand]) {
        store.replaceAll(commands)
        reload()
    }

    func reloadTargets() {
        for p in [edTargetPopup] {
            let keep = p.indexOfSelectedItem
            p.removeAllItems()
            p.addItem(withTitle: L10n.t("cmd.current"))
            p.addItem(withTitle: L10n.t("cmd.allConnected"))
            for s in (sessionsProvider?() ?? []) where s.connected {
                p.addItem(withTitle: s.title)
            }
            if keep >= 0, keep < p.numberOfItems { p.selectItem(at: keep) }
        }
    }
    private func currentTarget() -> SendTarget { target(of: edTargetPopup) }

    private func target(of popup: NSPopUpButton) -> SendTarget {
        switch popup.indexOfSelectedItem {
        case 0: return .current
        case 1: return .allConnected
        default:
            // 下标 2 起对应"已连接会话"顺序
            let connectedIdx = popup.indexOfSelectedItem - 2
            let all = sessionsProvider?() ?? []
            var seen = -1
            for (i, s) in all.enumerated() where s.connected {
                seen += 1
                if seen == connectedIdx { return .session(i) }
            }
            return .current
        }
    }

    /// 分类做成**文件夹样式**并自动换行（老仓库就是一排 📁 排满折行）
    private func reloadGroups() {
        var items: [NSView] = []
        let groups = store.groups()
        // 第一次打开选中用户排序中的第一个文件夹；「全部」只作为最后一个入口。
        if !didSelectInitialGroup {
            selectedGroup = groups.first
            didSelectInitialGroup = true
        }
        for g in groups {
            items.append(folderChip(g, key: g, on: selectedGroup == g))
        }
        items.append(folderChip(L10n.t("cmd.all"), key: "", on: selectedGroup == nil))
        groupFlow.setReorderableItems(items, draggableCount: groups.count) { [weak self] from, to in
            guard let self, groups.indices.contains(from) else { return }
            self.store.reorderGroup(groups[from], to: min(to, max(0, groups.count - 1)))
            self.reloadGroups()
        }
    }

    /// 分组 chip。图标用 **SF Symbol 图片**而不是 🗀 之类的字形 ——
    /// 系统字体里没有那些码位，会渲染成"?"豆腐块（第一版就踩了）。
    private func folderChip(_ title: String, key: String, on: Bool) -> PillButton {
        let b = PillButton(title, style: on ? .primary : .secondary, hPad: 8, height: 22,
                           font: Theme.ui(11), target: self, action: #selector(pickGroup(_:)))
        b.image = NSImage(systemSymbolName: on ? "folder.fill" : "folder", accessibilityDescription: "分组")
        b.imagePosition = .imageLeading
        b.imageHugsTitle = true
        b.contentTintColor = on ? .white : Theme.muted
        b.identifier = .init(key)
        b.menu = groupMenu(key)       // 右键分组本身：重命名 / 删除
        return b
    }

    /// 分组 chip 的右键菜单
    private func groupMenu(_ key: String) -> NSMenu {
        let m = NSMenu()
        add(m, "新建分组…", #selector(newGroup))
        add(m, "添加命令…", #selector(newCommand))
        if !key.isEmpty {
            m.addItem(.separator())
            m.addItem(sortMenu(title: "分组排序", id: key, action: #selector(sortGroup(_:))))
            add(m, "重命名分组…", #selector(renameGroup(_:)), key)
            add(m, "删除分组", #selector(deleteGroup(_:)), key)
        }
        return m
    }

    /// 菜单项小工具：统一挂 target 并把 id 放进 representedObject
    private func add(_ m: NSMenu, _ title: String, _ sel: Selector, _ rep: Any? = nil) {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self; it.representedObject = rep
        m.addItem(it)
    }
    @objc private func pickGroup(_ sender: NSButton) {
        let g = sender.identifier?.rawValue ?? ""
        selectedGroup = g.isEmpty ? nil : g
        reloadGroups(); reloadChips()
    }

    /// 命令列表：每条 = [名称按钮][⚙]，整体换行铺开（老仓库的样子）
    private func reloadChips() {
        var items: [NSView] = []
        let commands = store.list(group: selectedGroup)
        if !commands.contains(where: { $0.id == selectedCmdId }) { selectedCmdId = commands.first?.id }
        for c in commands {
            let hasParam = !(c.params?.isEmpty ?? true) || CommandParams.hasUnresolved(c.command)
            let isSel = (selectedCmdId == c.id)
            // 参数状态由下方详情栏呈现，列表名称不再追加“⋯”，避免与截断符混淆。
            let name = PillButton(c.name,
                                  style: isSel ? .primary : .ghost, hPad: 0, height: 22,
                                  font: Theme.ui(11), target: self, action: #selector(chipClicked(_:)))
            name.identifier = .init(c.id)
            name.toolTip = c.command
            name.menu = chipMenu(c.id)

            // ⚙ = 这条命令的编辑/删除入口（老仓库每条命令后面都有个齿轮）
            let gear = PillButton("⚙", style: .ghost, hPad: 0, height: 22,
                                  font: Theme.ui(11), target: self, action: #selector(gearClicked(_:)))
            gear.foregroundColorOverride = hasParam ? Theme.accent : nil
            gear.identifier = .init(c.id)
            gear.toolTip = "编辑 / 删除"

            let cell = NSStackView(views: [name, gear])
            cell.orientation = .horizontal; cell.spacing = 0; cell.alignment = .centerY
            cell.translatesAutoresizingMaskIntoConstraints = false
            items.append(cell)
        }
        cmdFlow.setReorderableItems(items) { [weak self] from, to in
            guard let self, commands.indices.contains(from) else { return }
            if self.selectedGroup == nil {
                self.store.reorderAllCommands(from: from, to: to)
            } else {
                self.store.reorderCommand(commands[from].id, to: to)
            }
            self.reloadChips()
        }
        if let id = selectedCmdId, let command = commands.first(where: { $0.id == id }) {
            showParameterForm(for: command, target: .current, names: CommandParams.parse(command.command))
        } else {
            clearCommandDetails()
        }
    }
    /// 命令的右键/齿轮菜单（项目对齐参考图；老仓库叫"文件夹"，这里统一叫**分组** —— 同一个东西）
    private func chipMenu(_ id: String) -> NSMenu {
        let m = NSMenu()
        add(m, "添加命令…", #selector(newCommand))
        add(m, "复制命令", #selector(copyCommandText(_:)), id)
        add(m, "编辑", #selector(editCommand(_:)), id)
        add(m, "删除", #selector(deleteCommand(_:)), id)
        m.addItem(sortMenu(title: "命令排序", id: id, action: #selector(sortCommand(_:))))
        m.addItem(.separator())
        add(m, "新建分组…", #selector(newGroup))

        // 移动到 ▸ <各分组>
        let moveItem = NSMenuItem(title: "移动到", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let cur = store.commands.first(where: { $0.id == id })?.group ?? "默认"
        for g in store.groups() {
            let it = NSMenuItem(title: g, action: #selector(moveCommand(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = ["id": id, "group": g]
            it.state = (g == cur) ? .on : .off      // 当前所在分组打勾
            sub.addItem(it)
        }
        moveItem.submenu = sub
        m.addItem(moveItem)
        return m
    }

    /// 排序入口放入右键子菜单，不占用命令列表的常驻空间。
    private func sortMenu(title: String, id: String, action: Selector) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for (label, position) in [("移到最前", "first"), ("向前", "previous"),
                                  ("向后", "next"), ("移到最后", "last")] {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self; item.representedObject = ["id": id, "position": position]
            menu.addItem(item)
        }
        root.submenu = menu
        return root
    }

    /// 命令列表**空白处**右键：只有"新建分组/添加命令"（对齐参考图第一张）
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        add(m, "新建分组…", #selector(newGroup))
        add(m, "添加命令…", #selector(newCommand))
        return m
    }

    // MARK: 动作
    /// 单击命令选中并显示详情；原按钮保持不重建，确保第二次点击能被识别为双击。
    @objc private func chipClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let command = store.commands.first(where: { $0.id == id }) else { return }
        selectedCmdId = id
        // 只更新现有按钮样式，不在第一次单击时重建列表，否则双击序列会中断。
        for case let cell as NSStackView in cmdFlow.subviews {
            guard let button = cell.arrangedSubviews.first as? PillButton else { continue }
            button.style = button.identifier?.rawValue == id ? .primary : .ghost
        }
        let names = CommandParams.parse(command.command)
        showParameterForm(for: command, target: target(of: paramTargetPopup), names: names)
        if NSApp.currentEvent?.clickCount ?? 1 >= 2, names.isEmpty {
            sendCommand(command, to: target(of: paramTargetPopup))
        }
    }

    /// 发送一条命令（含 ${参数} 逐个询问）—— 双击和左栏「发送」共用
    private func sendCommand(_ c: QuickCommand, to tgt: SendTarget) {
        // 先解析原始模板。旧代码先套默认值，导致占位符消失，双击直接发送。
        let names = CommandParams.parse(c.command)
        if !names.isEmpty {
            showParameterForm(for: c, target: tgt, names: names)
            return
        }
        let suffix = (c.autoReturn ?? true) ? "\r" : ""
        onSendTo?(c.command + suffix, tgt)
    }

    private func showParameterForm(for command: QuickCommand, target: SendTarget, names: [String]) {
        pendingTemplate = command.command
        pendingAutoReturn = command.autoReturn ?? true
        detailName.title = command.name
        detailName.style = .primary
        detailCommand.stringValue = command.command.replacingOccurrences(of: "\n", with: "  ")
        paramTargetPopup.selectItem(at: target == .allConnected ? 1 : 0)
        paramInputs.removeAll()
        paramFields.arrangedSubviews.forEach { paramFields.removeArrangedSubview($0); $0.removeFromSuperview() }
        let history = UserDefaults.standard.dictionary(forKey: Self.paramHistoryKey) as? [String: [String]] ?? [:]
        for name in names {
            let declared = command.params?.first { $0.name == name }
            let values = history[name] ?? []
            let label = small(name + (declared?.required == true ? " *" : ""))
            let combo = NSComboBox()
            combo.font = Theme.ui(11)
            combo.focusRingType = .none
            combo.usesDataSource = false
            combo.addItems(withObjectValues: values)
            combo.stringValue = values.first ?? declared?.defaultValue
                ?? CommandParams.defaultValue(command.command, for: name) ?? ""
            combo.translatesAutoresizingMaskIntoConstraints = false
            // 固定为紧凑宽度，防止第一个参数抢占整行剩余空间。
            combo.widthAnchor.constraint(equalToConstant: 150).isActive = true
            combo.setContentHuggingPriority(.required, for: .horizontal)
            // 标签与输入框同行显示，避免参数区为单个参数占用两行高度。
            let field = NSStackView(views: [label, combo])
            field.orientation = .horizontal; field.alignment = .centerY; field.spacing = 5
            paramFields.addArrangedSubview(field)
            paramInputs[name] = combo
        }
        let fields = paramFields.arrangedSubviews
        paramFieldsWidthC.constant = fields.reduce(0) { $0 + $1.fittingSize.width }
            + CGFloat(max(0, fields.count - 1)) * paramFields.spacing
        paramFields.isHidden = names.isEmpty
        paramBox.isHidden = false
        paramHeightC.constant = 58
        needsLayout = true
        window?.makeFirstResponder(paramInputs[names.first ?? ""])
    }

    @objc private func confirmParamsAction() {
        guard let template = pendingTemplate else { return }
        var values: [String: String] = [:]
        for (name, input) in paramInputs {
            values[name] = input.stringValue
            rememberParam(name, value: input.stringValue)
        }
        let text = CommandParams.render(template, values: values)
        // 参数表单只提供用户要求的两种批量范围；指定单会话仍由编辑器发送栏负责。
        let target: SendTarget = paramTargetPopup.indexOfSelectedItem == 1 ? .allConnected : .current
        let suffix = pendingAutoReturn ? "\r" : ""
        onSendTo?(text + suffix, target)
    }

    @objc private func cancelParamsAction() {
        guard let id = selectedCmdId,
              let command = store.commands.first(where: { $0.id == id }) else { return }
        showParameterForm(for: command, target: .current, names: CommandParams.parse(command.command))
    }

    private func clearCommandDetails() {
        pendingTemplate = nil
        pendingAutoReturn = true
        detailName.title = "请选择命令"
        detailName.style = .primary
        detailCommand.stringValue = ""
        paramInputs.removeAll()
        paramFields.arrangedSubviews.forEach { paramFields.removeArrangedSubview($0); $0.removeFromSuperview() }
        paramFieldsWidthC.constant = 0
        paramFields.isHidden = true
        paramBox.isHidden = false
        paramHeightC.constant = 58
        needsLayout = true
    }

    private func rememberParam(_ name: String, value: String) {
        guard !value.isEmpty else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.paramHistoryKey) as? [String: [String]] ?? [:]
        var values = all[name] ?? []
        values.removeAll { $0 == value }
        values.insert(value, at: 0)
        all[name] = Array(values.prefix(parameterHistoryLimit))
        UserDefaults.standard.set(all, forKey: Self.paramHistoryKey)
    }

    @objc private func gearClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              store.commands.contains(where: { $0.id == id }) else { return }
        selectedCmdId = id
        reloadChips()
    }

    @objc private func editSelectedCommand() {
        guard let id = selectedCmdId else { NSSound.beep(); return }
        let item = NSMenuItem(); item.representedObject = id
        editCommand(item)
    }

    // MARK: - 右侧栏动作

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === editor, commandSelector == #selector(NSResponder.insertTab(_:)) else { return false }
        onCompleteEditor?(textView.string) { [weak self] candidates in
            guard let self else { return }
            self.showCompletionCandidates(candidates)
        }
        return true
    }

    private func showCompletionCandidates(_ candidates: [(title: String, value: String)]) {
        completionPopover?.close()
        guard !candidates.isEmpty else { NSSound.beep(); return }
        let vc = CompletionListVC()
        vc.items = candidates
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        vc.onSelect = { [weak self, weak pop] value in
            guard let self else { return }
            self.editor.string = value
            self.editor.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
            self.window?.makeFirstResponder(self.editor)
            pop?.close()
        }
        completionPopover = pop
        // 始终从编辑器同一侧弹出；候选窗高度固定，避免项目少时跳到另一侧。
        pop.show(relativeTo: editorScroll.bounds, of: editorScroll, preferredEdge: .minY)
    }

    @objc private func showHistory(_ sender: NSButton) {
        onShowHistory?(sender)
    }

    @objc private func sendEditor() {
        let sel = editor.selectedRange()
        let ns = editor.string as NSString
        let text = sel.length > 0 ? ns.substring(with: sel) : editor.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        onSendTo?(text.hasSuffix("\n") ? text : text + "\n", target(of: edTargetPopup))
    }

    /// 右栏「选项」：编辑器上的一些顺手操作
    @objc private func editorOptions(_ sender: NSButton) {
        let m = NSMenu()
        func add(_ t: String, _ a: Selector) {
            let it = NSMenuItem(title: t, action: a, keyEquivalent: ""); it.target = self; m.addItem(it)
        }
        add("清空编辑器", #selector(clearEditor))
        add("把选中项载入编辑器", #selector(loadSelectedIntoEditor))
        m.addItem(.separator())
        add("存为新命令…", #selector(saveEditorAsCommand))
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }
    @objc private func clearEditor() { editor.string = "" }
    @objc private func loadSelectedIntoEditor() {
        guard let id = selectedCmdId, let c = store.commands.first(where: { $0.id == id }) else { return }
        editor.string = c.command
    }
    func setParameterHistoryLimit(_ requested: Int) {
        let value = min(500, max(1, requested))
        UserDefaults.standard.set(value, forKey: Self.paramHistoryLimitKey)
        var all = UserDefaults.standard.dictionary(forKey: Self.paramHistoryKey) as? [String: [String]] ?? [:]
        for (name, values) in all { all[name] = Array(values.prefix(value)) }
        UserDefaults.standard.set(all, forKey: Self.paramHistoryKey)
    }
    @objc private func saveEditorAsCommand() {
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { NSSound.beep(); return }
        guard let n = ask("存为新命令", "给它起个名字", defaultValue: "") , !n.isEmpty else { return }
        var item = QuickCommand(name: n, command: text)
        item.group = selectedGroup ?? "默认"
        store.upsert(item)
        reloadGroups(); reloadChips()
    }

    /// 收起 = 右栏缩成窄条（左栏顺势占满）。
    /// **坑**：第一版收起后就打不开了 —— 收起按钮本身在右栏头部，栏宽只剩 30pt 时
    /// 它连同标题一起被挤出可见区，没有任何可点的东西。所以收起态要换成一个
    /// **占满整条窄栏的展开按钮**（expandStrip），点它恢复。
    @objc private func toggleEditor() {
        setEditorCollapsed(!editorCollapsed)
    }
    @objc private func expandEditor() { setEditorCollapsed(false) }

    /// 拖动中间手柄自由调整左右栏宽度；右栏宽度持久化，下次启动继续使用。
    @objc private func resizeColumns(_ gesture: NSPanGestureRecognizer) {
        guard !editorCollapsed else { return }
        switch gesture.state {
        case .began:
            resizeStartRightWidth = rightWidthC.constant
        case .changed:
            let dx = gesture.translation(in: self).x
            let minimumRight: CGFloat = 180
            let minimumLeft: CGFloat = 260
            let maximumRight = max(minimumRight, bounds.width - minimumLeft - 44)
            rightWidthC.constant = min(maximumRight, max(minimumRight, resizeStartRightWidth - dx))
            needsLayout = true
        case .ended:
            UserDefaults.standard.set(Double(rightWidthC.constant), forKey: Self.rightWidthKey)
        default:
            break
        }
    }

    private func setEditorCollapsed(_ collapsed: Bool) {
        editorCollapsed = collapsed
        let saved = UserDefaults.standard.double(forKey: Self.rightWidthKey)
        let expandedWidth = saved > 0 ? CGFloat(saved) : Self.rightExpanded
        rightWidthC.constant = collapsed ? Self.rightCollapsed : expandedWidth
        // 展开态的三块内容
        for v in editorParts { v.isHidden = collapsed }
        // 收起态的窄条按钮
        expandStrip.isHidden = !collapsed
        needsLayout = true
    }

    @objc private func newGroup() {
        guard let n = ask("新建分组", "分组名", defaultValue: ""), !n.isEmpty else { return }
        guard store.addGroup(n) else { NSSound.beep(); return }   // 同名already存在
        selectedGroup = n
        reloadGroups(); reloadChips()
    }
    @objc private func renameGroup(_ sender: NSMenuItem) {
        guard let old = sender.representedObject as? String,
              let n = ask("重命名分组", "把「\(old)」改成", defaultValue: old), !n.isEmpty else { return }
        store.renameGroup(old, to: n)
        if selectedGroup == old { selectedGroup = n }
        reloadGroups(); reloadChips()
    }
    @objc private func deleteGroup(_ sender: NSMenuItem) {
        guard let g = sender.representedObject as? String else { return }
        let a = NSAlert.pix()
        a.messageText = "删除分组「\(g)」？"
        a.informativeText = "里面的命令会移回「默认」分组，命令本身不会被删。"
        a.addButton(withTitle: "删除分组"); a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        store.removeGroup(g)
        if selectedGroup == g { selectedGroup = nil }
        reloadGroups(); reloadChips()
    }
    @objc private func sortGroup(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: String],
              let name = data["id"], let position = data["position"] else { return }
        let groups = store.groups()
        guard let current = groups.firstIndex(of: name) else { return }
        store.reorderGroup(name, to: sortDestination(position, current: current, count: groups.count))
        reloadGroups(); reloadChips()
    }

    @objc private func sortCommand(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: String],
              let id = data["id"], let position = data["position"],
              let command = store.commands.first(where: { $0.id == id }) else { return }
        let group = command.group.isEmpty ? "默认" : command.group
        let commands = store.commands.filter { ($0.group.isEmpty ? "默认" : $0.group) == group }
        guard let current = commands.firstIndex(where: { $0.id == id }) else { return }
        store.reorderCommand(id, to: sortDestination(position, current: current, count: commands.count))
        reloadChips()
    }

    private func sortDestination(_ position: String, current: Int, count: Int) -> Int {
        switch position {
        case "first": return 0
        case "previous": return max(0, current - 1)
        case "next": return min(max(0, count - 1), current + 1)
        case "last": return max(0, count - 1)
        default: return current
        }
    }
    /// 复制命令 = 把**命令文本**丢进剪贴板（方便贴到别处），不是复制出一条新命令。
    @objc private func copyCommandText(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let c = store.commands.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(c.command, forType: .string)
    }
    @objc private func moveCommand(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? [String: String],
              let id = d["id"], let g = d["group"] else { return }
        store.move(id, to: g)
        reloadGroups(); reloadChips()
    }

    @objc private func newCommand() { editCommand(nil) }
    @objc private func editCommand(_ sender: Any?) {
        let id = (sender as? NSMenuItem)?.representedObject as? String
        let existing = id.flatMap { i in store.commands.first(where: { $0.id == i }) }
        let a = NSAlert.pix()
        a.messageText = existing == nil ? "新建快捷命令" : "编辑快捷命令"
        a.addButton(withTitle: "保存"); a.addButton(withTitle: "取消")
        let name = NSTextField(string: existing?.name ?? "")
        let group = NSTextField(string: existing?.group ?? "默认")

        let cmdScroll = NSScrollView()
        cmdScroll.borderType = .bezelBorder
        cmdScroll.hasVerticalScroller = true
        cmdScroll.autohidesScrollers = true
        let cmdView = NSTextView()
        cmdView.isRichText = false
        cmdView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        cmdView.string = existing?.command ?? ""
        cmdView.autoresizingMask = [.width]
        cmdScroll.documentView = cmdView

        let autoReturn = NSButton(checkboxWithTitle: "末尾添加回车符CR", target: nil, action: nil)
        autoReturn.state = (existing?.autoReturn ?? true) ? .on : .off

        for f in [name, group] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }
        cmdScroll.translatesAutoresizingMaskIntoConstraints = false
        cmdScroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        cmdScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let grid = NSGridView(numberOfColumns: 2, rows: 0); grid.rowSpacing = 8; grid.columnSpacing = 10
        grid.addRow(with: [NSTextField(labelWithString: "名称"), name])
        grid.addRow(with: [NSTextField(labelWithString: "分组"), group])

        let cmdLabel = NSTextField(labelWithString: "命令")
        grid.addRow(with: [cmdLabel, cmdScroll])
        grid.cell(for: cmdLabel)?.yPlacement = .top

        grid.addRow(with: [NSTextField(labelWithString: ""), autoReturn])

        let hint = NSTextField(labelWithString: "支持 ${参数}，发送时会提示填写")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        grid.addRow(with: [NSTextField(labelWithString: ""), hint])

        grid.frame = NSRect(x: 0, y: 0, width: 480, height: 230)
        a.accessoryView = grid

        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = name.stringValue.trimmingCharacters(in: .whitespaces)
        let c = cmdView.string.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !c.isEmpty else { return }
        var item = existing ?? QuickCommand(name: n, command: c)
        item.name = n; item.command = c
        item.group = group.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? "默认" : group.stringValue
        item.autoReturn = autoReturn.state == .on
        store.upsert(item)
        reloadGroups(); reloadChips()
    }
    @objc private func deleteCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.delete(id); reloadGroups(); reloadChips()
    }

    private func ask(_ title: String, _ info: String, defaultValue: String) -> String? {
        let a = NSAlert.pix(); a.messageText = title; a.informativeText = info
        a.addButton(withTitle: "确定"); a.addButton(withTitle: "取消")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        tf.stringValue = defaultValue
        a.accessoryView = tf; a.window.initialFirstResponder = tf
        return a.runModal() == .alertFirstButtonReturn ? tf.stringValue : nil
    }
}

/// Tab 补全候选窗：与历史窗口一致使用弹出式滚动列表，候选可直接点击写入编辑器。
private final class CompletionListVC: NSViewController {
    var items: [(title: String, value: String)] = []
    var onSelect: ((String) -> Void)?
    private var buttons: [PillButton] = []
    private var selectedIndex = 0
    private var keyMonitor: Any?

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true; root.layer?.backgroundColor = Theme.bg.cgColor
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack); scroll.documentView = doc; root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        for (index, item) in items.enumerated() {
            let button = PillButton(item.title, style: .ghost, hPad: 7, height: 24,
                                    font: Theme.mono(11), target: self, action: #selector(selectItem(_:)))
            button.tag = index; button.alignment = .left
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            buttons.append(button)
        }
        // 固定尺寸确保候选少或多时弹窗位置一致；内容不足处留白，过多时滚动。
        root.frame = NSRect(x: 0, y: 0, width: 420, height: 260)
        view = root
        updateSelection()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125: // ↓
                self.selectedIndex = min(self.items.count - 1, self.selectedIndex + 1)
                self.updateSelection(); return nil
            case 126: // ↑
                self.selectedIndex = max(0, self.selectedIndex - 1)
                self.updateSelection(); return nil
            case 36, 76: // Return / keypad Enter
                self.confirmSelection(); return nil
            case 53: // Esc
                self.view.window?.performClose(nil); return nil
            default:
                return event
            }
        }
    }

    @objc private func selectItem(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag].value)
    }

    private func updateSelection() {
        guard !buttons.isEmpty else { return }
        for (index, button) in buttons.enumerated() {
            button.style = index == selectedIndex ? .primary : .ghost
        }
        buttons[selectedIndex].scrollToVisible(buttons[selectedIndex].bounds)
    }

    private func confirmSelection() {
        guard items.indices.contains(selectedIndex) else { return }
        onSelect?(items[selectedIndex].value)
    }
}
