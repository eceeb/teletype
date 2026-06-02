import AppKit

/// Where the tab bar sits.
enum TabPlacement: String {
    case top
    case left
}

/// A simple tab bar: one button per tab plus a "+" button. Lays its buttons out
/// horizontally (top placement) or vertically (left placement).
@MainActor
final class TabBarView: NSView {
    private let stack = NSStackView()
    var onSelect: ((Int) -> Void)?
    var onNew: (() -> Void)?

    var placement: TabPlacement = .top {
        didSet {
            stack.orientation = (placement == .top) ? .horizontal : .vertical
            stack.alignment = (placement == .top) ? .centerY : .leading
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(count: Int, active: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for index in 0..<count {
            let button = NSButton(title: "Tab \(index + 1)", target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.setButtonType(.pushOnPushOff)
            button.state = (index == active) ? .on : .off
            stack.addArrangedSubview(button)
        }
        let plus = NSButton(title: "+", target: self, action: #selector(addTab(_:)))
        plus.bezelStyle = .rounded
        stack.addArrangedSubview(plus)
    }

    @objc private func selectTab(_ sender: NSButton) { onSelect?(sender.tag) }
    @objc private func addTab(_ sender: NSButton) { onNew?() }
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
            let barHeight: CGFloat = 32
            tabBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
            content.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: max(0, bounds.height - barHeight))
        case .left:
            let barWidth: CGFloat = 140
            tabBar.frame = NSRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            content.frame = NSRect(x: barWidth, y: 0, width: max(0, bounds.width - barWidth), height: bounds.height)
        }
    }
}
