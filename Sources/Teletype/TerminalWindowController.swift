import AppKit
import Foundation
import TeletypeCore

/// Owns one tab: its window and the panes inside it. For now a tab has a single
/// pane; splitting (Cmd-D / Cmd-Shift-D) will add more.
@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    private var panes: [TerminalPane] = []

    /// Called when this tab's window closes, so the app can release it.
    var onClose: ((TerminalWindowController) -> Void)?
    /// Called when this tab's window becomes key (for MRU tab tracking).
    var onActivated: ((TerminalWindowController) -> Void)?

    init() {
        let pane = TerminalPane()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "teletype"
        window.tabbingIdentifier = "teletype"
        window.contentView = pane.view

        super.init(window: window)
        window.delegate = self

        // When a pane's shell exits, close just that pane (last one closes the tab).
        pane.onExit = { [weak self, weak pane] in
            if let pane { self?.closePane(pane) }
        }
        panes.append(pane)
        pane.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func focusTerminal() {
        if let pane = panes.first {
            window?.makeFirstResponder(pane.view)
        }
    }

    // MARK: - Splitting

    @objc func splitRight(_ sender: Any?) { splitActivePane(vertical: true) }
    @objc func splitDown(_ sender: Any?) { splitActivePane(vertical: false) }
    @objc func closeActivePane(_ sender: Any?) {
        if let active = activePane { closePane(active) }
    }

    /// The pane currently holding keyboard focus (falls back to the last one).
    private var activePane: TerminalPane? {
        if let responder = window?.firstResponder as? NSView,
           let pane = panes.first(where: { $0.view == responder || responder.isDescendant(of: $0.view) }) {
            return pane
        }
        return panes.last
    }

    /// Splits the active pane in two, the new pane beside it (vertical divider)
    /// or below it (horizontal divider). Nested splits form a tree of split views.
    private func splitActivePane(vertical: Bool) {
        guard let active = activePane else { return }
        let oldView = active.view

        let newPane = TerminalPane()
        newPane.onExit = { [weak self, weak newPane] in
            if let newPane { self?.closePane(newPane) }
        }
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
            window?.contentView = split
            split.addArrangedSubview(oldView)
            split.addArrangedSubview(newPane.view)
        }

        relayoutSplits()
        newPane.start()
        window?.makeFirstResponder(newPane.view)
    }

    private func closePane(_ pane: TerminalPane) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        panes.remove(at: index)
        pane.terminate()

        if panes.isEmpty {
            close()   // last pane → close the tab
            return
        }

        let view = pane.view
        let parentSplit = view.superview as? NSSplitView
        view.removeFromSuperview()

        // A split left with one child is redundant: replace it with that child
        // so the tree stays a clean set of two-way splits.
        if let parentSplit, parentSplit.arrangedSubviews.count == 1,
           let remaining = parentSplit.arrangedSubviews.first {
            if let grandparent = parentSplit.superview as? NSSplitView {
                let idx = grandparent.arrangedSubviews.firstIndex(of: parentSplit) ?? 0
                remaining.removeFromSuperview()
                grandparent.insertArrangedSubview(remaining, at: idx)
                parentSplit.removeFromSuperview()
            } else {
                remaining.removeFromSuperview()
                window?.contentView = remaining
            }
        }

        relayoutSplits()
        window?.makeFirstResponder(panes.last?.view)
    }

    /// Forces a layout pass and evenly distributes every split (top-down), so
    /// freshly inserted and nested panes always get visible space.
    private func relayoutSplits() {
        guard let content = window?.contentView else { return }
        content.layoutSubtreeIfNeeded()
        evenlyDistribute(content)
    }

    private func evenlyDistribute(_ view: NSView) {
        guard let split = view as? NSSplitView else { return }
        if split.arrangedSubviews.count == 2 {
            let position = split.isVertical ? split.bounds.width / 2 : split.bounds.height / 2
            split.setPosition(position, ofDividerAt: 0)
        }
        split.layoutSubtreeIfNeeded()
        split.arrangedSubviews.forEach { evenlyDistribute($0) }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        onActivated?(self)
    }

    func windowWillClose(_ notification: Notification) {
        panes.forEach { $0.terminate() }
        onClose?(self)
    }
}
