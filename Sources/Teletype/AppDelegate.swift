import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Live terminal windows (tabs). Holding them keeps each one alive.
    private var controllers: [TerminalWindowController] = []
    /// Tabs in most-recently-used order (front = current). Drives Ctrl-Tab.
    private var mru: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        openTerminal()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Creates a terminal window. If `existing` is given, the new window is
    /// added as a tab next to it; otherwise it opens standalone.
    @discardableResult
    func openTerminal(tabbedTo existing: NSWindow? = nil, executable: String? = nil) -> TerminalWindowController {
        let controller = TerminalWindowController(executable: executable)
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
            self?.mru.removeAll { $0 === closed }
        }
        controller.onActivated = { [weak self] activated in
            self?.markUsed(activated)
        }
        controllers.append(controller)
        markUsed(controller)

        if let existing, let newWindow = controller.window {
            existing.addTabbedWindow(newWindow, ordered: .above)
            // addTabbedWindow only inserts the tab — make it the active one so
            // the user can type in it right away.
            existing.tabGroup?.selectedWindow = newWindow
            newWindow.makeKeyAndOrderFront(nil)
        } else if let window = controller.window {
            // Standalone window: restore the saved frame (position + size), or
            // center on first run. AppKit then keeps it saved across launches.
            let autosaveName = NSWindow.FrameAutosaveName("TeletypeMainWindow")
            if !window.setFrameUsingName(autosaveName) {
                window.center()
            }
            window.setFrameAutosaveName(autosaveName)
            controller.showWindow(nil)
        }
        controller.focusTerminal()
        return controller
    }

    @objc func newTab(_ sender: Any?) {
        openTerminal(tabbedTo: NSApp.keyWindow)
    }

    /// Cmd-E: open a tab running the Claude CLI.
    @objc func newClaudeTab(_ sender: Any?) {
        withClaude { executable in
            _ = openTerminal(tabbedTo: NSApp.keyWindow, executable: executable)
        }
    }

    /// Cmd-Shift-E: open the Claude CLI in a new pane beside the active one.
    @objc func newClaudePane(_ sender: Any?) {
        withClaude { claude in
            controllers.first { $0.window == NSApp.keyWindow }?
                .splitActivePane(vertical: true, executable: claude)
        }
    }

    /// Resolves the Claude CLI and runs `action`, or shows an alert if missing.
    private func withClaude(_ action: (String) -> Void) {
        guard let claude = Self.resolveExecutable(named: "claude") else {
            let alert = NSAlert()
            alert.messageText = "Claude CLI not found"
            alert.informativeText = "Couldn't find 'claude' on your PATH. Install Claude Code, then try again."
            alert.runModal()
            return
        }
        action(claude)
    }

    /// Finds an executable by searching the inherited PATH.
    private static func resolveExecutable(named name: String) -> String? {
        let pathVariable = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for directory in pathVariable.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Cmd-1 … Cmd-9: select the tab whose index is the sender's tag (0-based).
    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        guard let group = NSApp.keyWindow?.tabGroup else { return }
        let windows = group.windows
        guard windows.indices.contains(sender.tag) else { return }
        group.selectedWindow = windows[sender.tag]
        focusController(for: windows[sender.tag])
    }

    /// Ctrl-Tab: jump back to the tab used right before the current one.
    @objc func selectLastUsedTab(_ sender: Any?) {
        guard mru.count >= 2 else { return }
        let target = mru[1]
        if let window = target.window {
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        target.focusTerminal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - MRU tracking

    private func markUsed(_ controller: TerminalWindowController) {
        mru.removeAll { $0 === controller }
        mru.insert(controller, at: 0)
    }

    private func focusController(for window: NSWindow) {
        controllers.first { $0.window === window }?.focusTerminal()
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit teletype",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Shell menu
        let shellItem = NSMenuItem()
        mainMenu.addItem(shellItem)
        let shellMenu = NSMenu(title: "Shell")
        shellItem.submenu = shellMenu

        let newTabItem = NSMenuItem(title: "New Tab",
                                    action: #selector(newTab(_:)),
                                    keyEquivalent: "t")
        newTabItem.target = self
        shellMenu.addItem(newTabItem)

        let claudeTabItem = NSMenuItem(title: "New Claude Tab",
                                       action: #selector(newClaudeTab(_:)),
                                       keyEquivalent: "e")
        claudeTabItem.target = self
        shellMenu.addItem(claudeTabItem)

        let claudePaneItem = NSMenuItem(title: "New Claude Pane",
                                        action: #selector(newClaudePane(_:)),
                                        keyEquivalent: "e")
        claudePaneItem.keyEquivalentModifierMask = [.command, .shift]
        claudePaneItem.target = self
        shellMenu.addItem(claudePaneItem)

        shellMenu.addItem(withTitle: "Close Pane",
                          action: #selector(TerminalWindowController.closeActivePane(_:)),
                          keyEquivalent: "w")

        shellMenu.addItem(.separator())

        let splitRightItem = NSMenuItem(title: "Split Right",
                                        action: #selector(TerminalWindowController.splitRight(_:)),
                                        keyEquivalent: "d")
        shellMenu.addItem(splitRightItem)
        let splitDownItem = NSMenuItem(title: "Split Down",
                                       action: #selector(TerminalWindowController.splitDown(_:)),
                                       keyEquivalent: "d")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(splitDownItem)

        shellMenu.addItem(.separator())

        // Ctrl-Tab → back to the last-used tab.
        let lastUsed = NSMenuItem(title: "Switch to Last Used Tab",
                                  action: #selector(selectLastUsedTab(_:)),
                                  keyEquivalent: "\t")
        lastUsed.keyEquivalentModifierMask = [.control]
        lastUsed.target = self
        shellMenu.addItem(lastUsed)

        shellMenu.addItem(.separator())

        // Cmd-1 … Cmd-9 jump straight to tab N.
        for number in 1...9 {
            let item = NSMenuItem(title: "Go to Tab \(number)",
                                  action: #selector(selectTabByNumber(_:)),
                                  keyEquivalent: "\(number)")
            item.tag = number - 1
            item.target = self
            shellMenu.addItem(item)
        }

        // Edit menu (Paste for now; copy/selection comes with mouse selection)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")

        NSApp.mainMenu = mainMenu
    }
}
