import AppKit
import TeletypeCore

/// One tab: a tree of split panes inside `containerView`. The window shows the
/// active tab's container. Owns all the split/close logic for its panes.
@MainActor
final class TerminalTab {
    let containerView = NSView()
    private(set) var panes: [TerminalPane] = []

    /// Called when the tab's last pane has closed, so the owner can drop the tab.
    var onEmpty: (() -> Void)?
    /// Called when a pane's title or working directory changes (refresh the bar).
    var onTitleChanged: (() -> Void)?

    init(executable: String? = nil, arguments: [String] = []) {
        containerView.autoresizingMask = [.width, .height]
        let pane = makePane()
        place(pane.view, asChildOf: containerView)
        panes.append(pane)
        pane.start(executable: executable, arguments: arguments)
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

        let split = NSSplitView()
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
        newPane.start(executable: executable)
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
