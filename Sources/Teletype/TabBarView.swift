import AppKit

/// Where the tab bar sits.
enum TabPlacement: String {
    case top
    case left
}

/// What the tab bar needs to show for one tab.
struct TabItem {
    let title: String
    let subtitle: String?
    /// Which tab this pane belongs to — drives the group background color.
    let groupIndex: Int
    /// Shared parent-folder name shown as the group header (nil = no header).
    let groupLabel: String?
}

/// A rich sidebar row (left placement): icon + title + subtitle, highlighted when active.
@MainActor
final class TabRowView: NSView {
    var onClick: (() -> Void)?

    init(item: TabItem, isActive: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        // Muted dark green: OLED-friendly (dark, low-saturation), strong contrast
        // against the light sidebar, and a nod to the app icon. Not bright blue.
        layer?.backgroundColor = isActive
            ? NSColor(srgbRed: 0.10, green: 0.42, blue: 0.30, alpha: 1).cgColor
            : NSColor.clear.cgColor

        let titleLabel = NSTextField(labelWithString: item.title.isEmpty ? "Shell" : item.title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = isActive ? .white : .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])

        if let subtitle = item.subtitle, !subtitle.isEmpty {
            // A command is running: title near the top, process name underneath.
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5).isActive = true
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 10, weight: .regular)
            subtitleLabel.textColor = isActive ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subtitleLabel)
            NSLayoutConstraint.activate([
                subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
            ])
        } else {
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// The tab bar: compact buttons across the top, or rich rows down the left.
@MainActor
final class TabBarView: NSView, NSTextFieldDelegate {
    var onSelect: ((Int) -> Void)?
    var onNew: (() -> Void)?
    /// Double-clicking a group header renames it: (groupIndex, newName); a blank
    /// name clears the override and restores the folder-derived label.
    var onRenameGroup: ((Int, String?) -> Void)?

    var placement: TabPlacement = .top {
        didSet { rebuild() }
    }

    private var items: [TabItem] = []
    private var activeIndex = 0
    private var tabViews: [NSView] = []
    private let plusButton = NSButton(title: "+", target: nil, action: nil)
    /// Clickable rects of the group headers, refreshed on each draw (left placement).
    private var headerBoxes: [(rect: NSRect, group: Int)] = []
    private var editField: NSTextField?
    private var editingGroup: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        plusButton.bezelStyle = .rounded
        plusButton.target = self
        plusButton.action = #selector(addTab)
        addSubview(plusButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func update(_ items: [TabItem], active: Int) {
        self.items = items
        self.activeIndex = active
        rebuild()
    }

    private func rebuild() {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews = items.enumerated().map { index, item in
            placement == .top ? makeButton(index, item) : makeRow(index, item)
        }
        tabViews.forEach { addSubview($0) }
        needsLayout = true
    }

    private func makeButton(_ index: Int, _ item: TabItem) -> NSView {
        let button = NSButton(title: item.title.isEmpty ? "Shell" : item.title,
                              target: self, action: #selector(buttonClicked(_:)))
        button.tag = index
        button.bezelStyle = .rounded
        button.setButtonType(.pushOnPushOff)
        button.state = (index == activeIndex) ? .on : .off
        return button
    }

    private func makeRow(_ index: Int, _ item: TabItem) -> NSView {
        let row = TabRowView(item: item, isActive: index == activeIndex)
        row.onClick = { [weak self] in self?.onSelect?(index) }
        return row
    }

    @objc private func buttonClicked(_ sender: NSButton) { onSelect?(sender.tag) }
    @objc private func addTab() { onNew?() }

    override func layout() {
        super.layout()
        switch placement {
        case .top:
            let height: CGFloat = 24
            let y = (bounds.height - height) / 2
            var x: CGFloat = 6
            for view in tabViews {
                let width = max(64, view.intrinsicContentSize.width + 8)
                view.frame = NSRect(x: x, y: y, width: width, height: height)
                x += width + 4
            }
            plusButton.frame = NSRect(x: x, y: y, width: 30, height: height)
        case .left:
            let baseHeight: CGFloat = 26
            let tallHeight: CGFloat = 42         // taller when a process subtitle shows
            let headerHeight: CGFloat = 18
            var y: CGFloat = 8
            var lastGroup = -1
            for (index, view) in tabViews.enumerated() {
                let item = items[index]
                if item.groupIndex != lastGroup {
                    if index != 0 { y += 16 }                // gap before a new group
                    if item.groupLabel != nil { y += headerHeight }
                    lastGroup = item.groupIndex
                }
                let rowHeight = (item.subtitle?.isEmpty == false) ? tallHeight : baseHeight
                view.frame = NSRect(x: 14, y: y, width: bounds.width - 24, height: rowHeight)
                y += rowHeight + 3
            }
            plusButton.frame = NSRect(x: 8, y: y + 6, width: bounds.width - 16, height: 24)
        }
        needsDisplay = true
    }

    /// Draws each group's colored rounded background + its parent-folder header.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        headerBoxes = []
        guard placement == .left else { return }
        var i = 0
        while i < tabViews.count, i < items.count {
            let group = items[i].groupIndex
            let label = items[i].groupLabel
            var last = i
            var j = i + 1
            while j < tabViews.count, j < items.count, items[j].groupIndex == group {
                last = j
                j += 1
            }
            let headerSpace: CGFloat = label != nil ? 18 : 0
            let top = tabViews[i].frame.minY - headerSpace - 4
            let bottom = tabViews[last].frame.maxY + 4
            let box = NSRect(x: 6, y: top, width: bounds.width - 12, height: bottom - top)
            groupColor(group).setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            if let label {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.labelColor
                ]
                (label as NSString).draw(at: NSPoint(x: 14, y: top + 3), withAttributes: attributes)
                headerBoxes.append((NSRect(x: box.minX, y: top, width: box.width, height: headerSpace), group))
            }
            i = j
        }
    }

    private func groupColor(_ index: Int) -> NSColor {
        // Muted, OLED-friendly tints (no bright blue); subtle on the sidebar.
        let palette: [NSColor] = [
            NSColor(srgbRed: 0.10, green: 0.42, blue: 0.30, alpha: 1),  // dark green (matches the active tab)
            NSColor(srgbRed: 0.16, green: 0.40, blue: 0.44, alpha: 1),  // muted teal
            NSColor(srgbRed: 0.52, green: 0.38, blue: 0.18, alpha: 1),  // muted amber
            NSColor(srgbRed: 0.40, green: 0.30, blue: 0.52, alpha: 1),  // muted plum
            NSColor(srgbRed: 0.52, green: 0.30, blue: 0.36, alpha: 1),  // muted rose
            NSColor(srgbRed: 0.34, green: 0.40, blue: 0.26, alpha: 1)   // muted olive
        ]
        return palette[index % palette.count].withAlphaComponent(0.20)
    }

    // MARK: - Renaming a group header

    /// Double-click on a header opens an inline editor for that group's name.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard placement == .left, event.clickCount == 2,
              let hit = headerBoxes.first(where: { $0.rect.contains(point) })
        else { return super.mouseDown(with: event) }
        beginRename(group: hit.group, in: hit.rect)
    }

    private func beginRename(group: Int, in rect: NSRect) {
        commitRename()        // close any editor already open
        let field = NSTextField(frame: NSRect(x: rect.minX, y: rect.minY,
                                               width: rect.width, height: max(rect.height, 20)))
        field.font = .systemFont(ofSize: 11, weight: .bold)
        field.stringValue = items.first { $0.groupIndex == group }?.groupLabel ?? ""
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitRenameAction)
        addSubview(field)
        editField = field
        editingGroup = group
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc private func commitRenameAction() { commitRename() }

    /// Applies the edited name (blank → nil, restoring the derived label) and
    /// tears the editor down. Idempotent so Enter + end-editing don't double-fire.
    private func commitRename() {
        guard let field = editField, let group = editingGroup else { return }
        editField = nil
        editingGroup = nil
        let value = field.stringValue
        field.removeFromSuperview()
        onRenameGroup?(group, value)
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }
}

/// Lays out the tab bar + content area, switching between top and left placement.
@MainActor
final class MainContentView: NSView {
    let tabBar: TabBarView
    let content = NSView()

    var placement: TabPlacement = .top {
        didSet {
            tabBar.placement = placement
            needsLayout = true
        }
    }

    init(tabBar: TabBarView) {
        self.tabBar = tabBar
        super.init(frame: .zero)
        addSubview(content)
        addSubview(tabBar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        switch placement {
        case .top:
            let barHeight: CGFloat = 36
            tabBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
            content.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: max(0, bounds.height - barHeight))
        case .left:
            let barWidth: CGFloat = 200
            tabBar.frame = NSRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            content.frame = NSRect(x: barWidth, y: 0, width: max(0, bounds.width - barWidth), height: bounds.height)
        }
    }
}
