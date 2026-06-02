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
}

/// A rich sidebar row (left placement): icon + title + subtitle, highlighted when active.
@MainActor
final class TabRowView: NSView {
    var onClick: (() -> Void)?

    init(item: TabItem, isActive: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor

        let titleLabel = NSTextField(labelWithString: item.title.isEmpty ? "Shell" : item.title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = isActive ? .white : .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// The tab bar: compact buttons across the top, or rich rows down the left.
@MainActor
final class TabBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onNew: (() -> Void)?

    var placement: TabPlacement = .top {
        didSet { rebuild() }
    }

    private var items: [TabItem] = []
    private var activeIndex = 0
    private var tabViews: [NSView] = []
    private let plusButton = NSButton(title: "+", target: nil, action: nil)

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
            let rowHeight: CGFloat = 30
            var y: CGFloat = 6
            for view in tabViews {
                view.frame = NSRect(x: 6, y: y, width: bounds.width - 12, height: rowHeight)
                y += rowHeight + 4
            }
            plusButton.frame = NSRect(x: 6, y: y, width: bounds.width - 12, height: 26)
        }
    }
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
