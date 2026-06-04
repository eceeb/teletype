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
        window.title = "teletype"
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

        newTab()
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
        tab.onEmpty = { [weak self, weak tab] in
            if let tab { self?.removeTab(tab) }
        }
        tab.onTitleChanged = { [weak self] in self?.refreshTabBar() }
        tabs.append(tab)
        selectTab(at: tabs.count - 1)
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
        paneRows = tabs.flatMap { tab in tab.panes.map { (tab: tab, pane: $0) } }
        let items = paneRows.map { TabItem(title: $0.pane.title, subtitle: nil) }
        let activeRow = activePaneRowIndex()
        let signature = "\(activeRow)#" + items.map { $0.title }.joined(separator: "/")
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

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        titleTimer?.invalidate()
        tabs.forEach { $0.terminateAll() }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }
}
