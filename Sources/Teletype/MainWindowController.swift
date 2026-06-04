import AppKit
import TeletypeCore

/// The single app window: holds all tabs, the tab bar, and the content area.
/// Replaces native window tabbing so the tab bar can sit top or left.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private var tabs: [TerminalTab] = []
    private var mru: [TerminalTab] = []          // most-recently-used (front = current)
    private var activeIndex = 0
    private let tabBar = TabBarView()
    private var rootView: MainContentView!
    private var settingsObserver: NSObjectProtocol?
    private var titleTimer: Timer?
    private var lastBarSignature = ""
    /// Flattened (tab, pane) list that the sidebar shows — one row per pane.
    private var paneRows: [(tab: TerminalTab, pane: TerminalPane)] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden   // most apps don't show their name in the title bar
        super.init(window: window)
        window.delegate = self

        rootView = MainContentView(tabBar: tabBar)
        rootView.placement = placementFromSettings()
        window.contentView = rootView

        tabBar.onSelect = { [weak self] index in self?.selectPaneRow(index) }
        tabBar.onNew = { [weak self] in self?.newTab() }

        // Restore saved frame (or center on first run) and keep it saved.
        let autosave = NSWindow.FrameAutosaveName("TeletypeMainWindow")
        if !window.setFrameUsingName(autosave) { window.center() }
        window.setFrameAutosaveName(autosave)

        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rootView.placement = self?.placementFromSettings() ?? .top }
        }

        // Poll for working-directory changes so tab titles stay current.
        titleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTabBar() }
        }

        restoreSession()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var activeTab: TerminalTab? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
    }

    private func placementFromSettings() -> TabPlacement {
        AppSettings.store.tabPlacement == "left" ? .left : .top
    }

    // MARK: - Tabs

    func newTab(executable: String? = nil) {
        let tab = TerminalTab(executable: executable)
        configure(tab)
        tabs.append(tab)
        selectTab(at: tabs.count - 1)
    }

    private func configure(_ tab: TerminalTab) {
        tab.onEmpty = { [weak self, weak tab] in
            if let tab { self?.removeTab(tab) }
        }
        tab.onTitleChanged = { [weak self] in self?.refreshTabBar() }
    }

    /// Recreates the saved session, or opens one fresh tab if there's nothing to restore.
    private func restoreSession() {
        guard let layout = SessionPersistence.load(), !layout.tabs.isEmpty else {
            newTab()
            return
        }
        for node in layout.tabs {
            let tab = TerminalTab(restoring: node)
            configure(tab)
            tabs.append(tab)
        }
        selectTab(at: 0)
    }

    private func saveSession() {
        SessionPersistence.save(SessionLayout(tabs: tabs.map { $0.layoutNode() }))
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        markUsed(tabs[index])
        showActiveTab()
        refreshTabBar()
        if let view = tabs[index].firstPaneView() { window?.makeFirstResponder(view) }
    }

    /// Makes the content area show the active tab's container, correctly sized.
    private func showActiveTab() {
        guard let tab = activeTab else { return }
        rootView.content.subviews.forEach { $0.removeFromSuperview() }
        rootView.layoutSubtreeIfNeeded()
        tab.containerView.frame = rootView.content.bounds
        tab.containerView.autoresizingMask = [.width, .height]
        rootView.content.addSubview(tab.containerView)
    }

    private func removeTab(_ tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tab.terminateAll()
        tabs.remove(at: index)
        mru.removeAll { $0 === tab }
        if tabs.isEmpty {
            close()           // last tab closed → close the window (and quit)
            return
        }
        if let next = mru.first, let nextIndex = tabs.firstIndex(where: { $0 === next }) {
            selectTab(at: nextIndex)
        } else {
            selectTab(at: min(index, tabs.count - 1))
        }
    }

    private func markUsed(_ tab: TerminalTab) {
        mru.removeAll { $0 === tab }
        mru.insert(tab, at: 0)
    }

    private func refreshTabBar() {
        paneRows = []
        var items: [TabItem] = []
        for (groupIndex, tab) in tabs.enumerated() {
            let cwds = tab.panes.map { $0.session.processWorkingDirectory() ?? "" }
            let summary = PaneGrouping.summarize(cwds)
            for (offset, pane) in tab.panes.enumerated() {
                paneRows.append((tab: tab, pane: pane))
                items.append(TabItem(title: pane.displayName ?? summary.labels[offset],
                                     subtitle: nil,
                                     groupIndex: groupIndex,
                                     groupLabel: summary.header))
            }
        }
        let activeRow = activePaneRowIndex()
        let signature = "\(activeRow)#" + items.map { "\($0.groupIndex):\($0.groupLabel ?? "")>\($0.title)" }.joined(separator: "|")
        guard signature != lastBarSignature else { return }
        lastBarSignature = signature
        tabBar.update(items, active: activeRow)
    }

    private func activePaneRowIndex() -> Int {
        guard let tab = activeTab, let active = tab.activePane(for: window?.firstResponder) else { return 0 }
        return paneRows.firstIndex(where: { $0.pane === active }) ?? 0
    }

    private func selectPaneRow(_ index: Int) {
        guard paneRows.indices.contains(index) else { return }
        let (tab, pane) = paneRows[index]
        if let tabIndex = tabs.firstIndex(where: { $0 === tab }), tabIndex != activeIndex {
            selectTab(at: tabIndex)
        }
        window?.makeFirstResponder(pane.view)
        refreshTabBar()
    }

    // MARK: - Menu actions (reached via the responder chain)

    @objc func newTabAction(_ sender: Any?) { newTab() }

    @objc func closeActivePane(_ sender: Any?) {
        guard let tab = activeTab, let active = tab.activePane(for: window?.firstResponder) else { return }
        tab.close(pane: active)   // last pane → tab.onEmpty → removeTab
        if tabs.contains(where: { $0 === tab }) {   // tab survived (had a split)
            showActiveTab()
            if let view = tab.firstPaneView() { window?.makeFirstResponder(view) }
        }
        refreshTabBar()
    }

    @objc func splitRight(_ sender: Any?) { splitActivePane(vertical: true) }
    @objc func splitDown(_ sender: Any?) { splitActivePane(vertical: false) }

    func splitActivePane(vertical: Bool, executable: String? = nil) {
        guard let tab = activeTab, let active = tab.activePane(for: window?.firstResponder) else { return }
        let newPane = tab.split(active, vertical: vertical, executable: executable)
        window?.makeFirstResponder(newPane.view)
        refreshTabBar()
    }

    @objc func selectLastUsedTab(_ sender: Any?) {
        guard mru.count >= 2, let index = tabs.firstIndex(where: { $0 === mru[1] }) else { return }
        selectTab(at: index)
    }

    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        selectTab(at: sender.tag)
    }

    // MARK: - Pane navigation

    @objc func selectPreviousPane(_ sender: Any?) { cyclePane(by: -1) }
    @objc func selectNextPane(_ sender: Any?) { cyclePane(by: 1) }

    private func cyclePane(by delta: Int) {
        guard !paneRows.isEmpty else { return }
        let next = (activePaneRowIndex() + delta + paneRows.count) % paneRows.count
        selectPaneRow(next)
    }

    @objc func focusPaneLeft(_ sender: Any?)  { focusPane(dx: -1, dy: 0) }
    @objc func focusPaneRight(_ sender: Any?) { focusPane(dx: 1, dy: 0) }
    @objc func focusPaneUp(_ sender: Any?)    { focusPane(dx: 0, dy: 1) }
    @objc func focusPaneDown(_ sender: Any?)  { focusPane(dx: 0, dy: -1) }

    /// Focuses the nearest pane in the active tab in the given direction
    /// (dx/dy in window coordinates, y growing upward).
    private func focusPane(dx: CGFloat, dy: CGFloat) {
        guard let tab = activeTab, let active = tab.activePane(for: window?.firstResponder) else { return }
        let from = active.view.convert(active.view.bounds, to: nil)
        let origin = CGPoint(x: from.midX, y: from.midY)
        var best: TerminalPane?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for pane in tab.panes where pane !== active {
            let frame = pane.view.convert(pane.view.bounds, to: nil)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let along = (center.x - origin.x) * dx + (center.y - origin.y) * dy
            guard along > 0 else { continue }   // only panes in the requested direction
            let distance = hypot(center.x - origin.x, center.y - origin.y)
            if distance < bestDistance {
                bestDistance = distance
                best = pane
            }
        }
        if let best {
            window?.makeFirstResponder(best.view)
            refreshTabBar()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveSession()                       // capture cwds before the shells die
        titleTimer?.invalidate()
        tabs.forEach { $0.terminateAll() }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }
}
