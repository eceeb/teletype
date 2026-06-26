import AppKit
import TeletypeCore

/// Split view with a dark-gray divider (the system default is a faint hairline).
@MainActor
final class PaneSplitView: NSSplitView {
    override var dividerColor: NSColor { NSColor(white: 0.25, alpha: 1) }
}

/// One tab: a tree of split panes inside `containerView`. The window shows the
/// active tab's container. Owns all the split/close logic for its panes.
@MainActor
final class TerminalTab {
    let containerView = NSView()
    private(set) var panes: [TerminalPane] = []

    /// User-given group name. While nil the sidebar header is derived from the
    /// panes' shared folder; once set it pins the header until edited again.
    var customName: String?

    /// Called when the tab's last pane has closed, so the owner can drop the tab.
    var onEmpty: (() -> Void)?
    /// Called when a pane's title or working directory changes (refresh the bar).
    var onTitleChanged: (() -> Void)?
    /// Called when one of this tab's panes gains focus (for pane MRU).
    var onPaneFocused: ((TerminalPane) -> Void)?

    init(executable: String? = nil, arguments: [String] = [], workingDirectory: String? = nil) {
        containerView.autoresizingMask = [.width, .height]
        let pane = makePane()
        place(pane.view, asChildOf: containerView)
        panes.append(pane)
        pane.start(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
    }

    /// Rebuilds a saved layout: recreates the split tree and opens each pane's
    /// shell in its remembered working directory.
    init(restoring node: PaneNode) {
        containerView.autoresizingMask = [.width, .height]
        place(buildView(from: node), asChildOf: containerView)
        relayout()
    }

    private func buildView(from node: PaneNode) -> NSView {
        switch node {
        case .leaf(let cwd):
            let pane = makePane()
            panes.append(pane)
            pane.start(workingDirectory: cwd)
            return pane.view
        case .split(let vertical, let children):
            let split = PaneSplitView()
            split.isVertical = vertical
            split.dividerStyle = .thin
            children.forEach { split.addArrangedSubview(buildView(from: $0)) }
            return split
        }
    }

    /// Captures the current split tree (with each pane's working directory) for saving.
    func layoutNode() -> PaneNode {
        guard let root = containerView.subviews.first else { return .leaf(cwd: nil) }
        return node(for: root)
    }

    private func node(for view: NSView) -> PaneNode {
        if let split = view as? NSSplitView {
            return .split(vertical: split.isVertical,
                          children: split.arrangedSubviews.map { node(for: $0) })
        }
        let pane = panes.first { $0.view == view }
        return .leaf(cwd: pane?.session.processWorkingDirectory())
    }

    // MARK: - Active pane / focus

    func firstPaneView() -> NSView? { panes.first?.view }

    /// The pane holding (or containing) the given first responder.
    func activePane(for firstResponder: NSResponder?) -> TerminalPane? {
        if let view = firstResponder as? NSView,
           let pane = panes.first(where: { $0.view == view || view.isDescendant(of: $0.view) }) {
            return pane
        }
        return panes.last
    }

    // MARK: - Splitting

    @discardableResult
    func split(_ active: TerminalPane, vertical: Bool, executable: String? = nil) -> TerminalPane {
        let oldView = active.view
        let newPane = makePane()
        panes.append(newPane)

        let split = PaneSplitView()
        split.isVertical = vertical
        split.dividerStyle = .thin

        if let parent = oldView.superview as? NSSplitView {
            let index = parent.arrangedSubviews.firstIndex(of: oldView) ?? 0
            oldView.removeFromSuperview()
            split.addArrangedSubview(oldView)
            split.addArrangedSubview(newPane.view)
            parent.insertArrangedSubview(split, at: index)
        } else {
            oldView.removeFromSuperview()
            place(split, asChildOf: containerView)
            split.addArrangedSubview(oldView)
            split.addArrangedSubview(newPane.view)
        }

        relayout()
        // A new split opens in the same directory as the pane it came from.
        newPane.start(executable: executable,
                      workingDirectory: active.session.processWorkingDirectory())
        return newPane
    }

    func close(pane: TerminalPane) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        panes.remove(at: index)
        pane.terminate()
        if panes.isEmpty { onEmpty?(); return }

        let view = pane.view
        let parentSplit = view.superview as? NSSplitView
        view.removeFromSuperview()

        // A split left with one child is redundant: hoist that child up.
        if let parentSplit, parentSplit.arrangedSubviews.count == 1,
           let remaining = parentSplit.arrangedSubviews.first {
            if let grandparent = parentSplit.superview as? NSSplitView {
                let idx = grandparent.arrangedSubviews.firstIndex(of: parentSplit) ?? 0
                remaining.removeFromSuperview()
                grandparent.insertArrangedSubview(remaining, at: idx)
                parentSplit.removeFromSuperview()
            } else {
                remaining.removeFromSuperview()
                place(remaining, asChildOf: containerView)
                parentSplit.removeFromSuperview()
            }
        }
        relayout()
    }

    func terminateAll() {
        panes.forEach { $0.terminate() }
    }

    // MARK: - Layout

    private func makePane() -> TerminalPane {
        let pane = TerminalPane()
        pane.onExit = { [weak self, weak pane] in
            if let pane { self?.close(pane: pane) }
        }
        pane.session.emulator.onTitleChange = { [weak self] in self?.onTitleChanged?() }
        pane.onFocus = { [weak self, weak pane] in
            if let pane { self?.onPaneFocused?(pane) }
        }
        return pane
    }

    /// Makes `view` the single, fully-sized child of `parent`. Resets
    /// `translatesAutoresizingMaskIntoConstraints` because NSSplitView turns it
    /// off on its arranged subviews — without this a pane pulled out of a split
    /// (on collapse) keeps a zero frame and renders blank.
    private func place(_ view: NSView, asChildOf parent: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = parent.bounds
        view.autoresizingMask = [.width, .height]
        parent.addSubview(view)
    }

    /// Forces layout and evenly distributes every split so nested panes stay visible.
    private func relayout() {
        containerView.layoutSubtreeIfNeeded()
        evenlyDistribute(containerView)
    }

    private func evenlyDistribute(_ view: NSView) {
        guard let split = view as? NSSplitView else {
            view.subviews.forEach { evenlyDistribute($0) }
            return
        }
        if split.arrangedSubviews.count == 2 {
            let position = split.isVertical ? split.bounds.width / 2 : split.bounds.height / 2
            split.setPosition(position, ofDividerAt: 0)
        }
        split.layoutSubtreeIfNeeded()
        split.arrangedSubviews.forEach { evenlyDistribute($0) }
    }
}
