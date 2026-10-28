import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var mainController: MainWindowController?
    private var settingsWindow: NSWindow?
    private var shortcutsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stop macOS from injecting Dictation / Emoji & Symbols into the Edit menu.
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
        AppIconCatalog.applyFromSettings()   // Dock icon the user picked in Settings
        setupMainMenu()
        let controller = MainWindowController()
        mainController = controller

        // `-probeQuietly` is for automated checks of a dev build: the window is
        // still real and still renders (so a screenshot of it works), but it
        // never takes focus or shows up in the Dock, which otherwise makes a
        // test run keep interrupting whoever is at the keyboard.
        if ProcessInfo.processInfo.arguments.contains("-probeQuietly") {
            NSApp.setActivationPolicy(.accessory)
            controller.window?.orderBack(nil)
            return
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// ⌘Q doesn't close windows, so `windowWillClose` never runs — without this
    /// the session saved on quit would be whatever was stored the last time the
    /// window itself was closed.
    func applicationWillTerminate(_ notification: Notification) {
        mainController?.saveSession()
    }

    // MARK: - Claude (resolve, then route into the main window)

    @objc func newClaudeTab(_ sender: Any?) {
        withClaude { mainController?.newTab(executable: $0) }
    }

    @objc func newClaudePane(_ sender: Any?) {
        withClaude { mainController?.splitActivePane(vertical: true, executable: $0) }
    }

    private func withClaude(_ action: (String) -> Void) {
        guard let claude = Self.resolveClaude() else {
            let alert = NSAlert()
            alert.messageText = "Claude CLI not found"
            alert.informativeText = "Couldn't find 'claude'. Set its path in Settings → Claude command, or install Claude Code."
            alert.runModal()
            return
        }
        action(claude)
    }

    /// Resolves the claude binary: the configured path/name first, otherwise an
    /// auto-search over PATH plus the usual install locations.
    private static func resolveClaude() -> String? {
        if let configured = AppSettings.store.claudeCommand, !configured.isEmpty {
            let expanded = (configured as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
            }
            return resolveExecutable(named: expanded)
        }
        return resolveExecutable(named: "claude")
    }

    private static func resolveExecutable(named name: String) -> String? {
        let fileManager = FileManager.default
        // A GUI app launched via /Applications gets a minimal PATH, so also probe
        // the common install dirs (Homebrew etc.) where `claude` usually lives.
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let common = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                      NSHomeDirectory() + "/.local/bin"]
        for directory in envPath.split(separator: ":").map(String.init) + common {
            let candidate = "\(directory)/\(name)"
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - Settings

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 380, height: 470))   // grew with the Bell row
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openShortcuts(_ sender: Any?) {
        if shortcutsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsView()))
            window.title = "Keyboard Shortcuts"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 420, height: 520))
            shortcutsWindow = window
        }
        shortcutsWindow?.center()
        shortcutsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Teletype",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        // Without these the standard ⌘H / ⌥⌘H do nothing at all: a key
        // equivalent only exists if some menu item carries it.
        appMenu.addItem(withTitle: "Hide Teletype",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Teletype",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Shell menu (tab/pane actions route via the responder chain to MainWindowController)
        let shellItem = NSMenuItem()
        mainMenu.addItem(shellItem)
        let shellMenu = NSMenu(title: "Shell")
        shellItem.submenu = shellMenu

        shellMenu.addItem(withTitle: "New Tab",
                          action: #selector(MainWindowController.newTabAction(_:)),
                          keyEquivalent: "t")
        let claudeTabItem = NSMenuItem(title: "New Claude Tab",
                                       action: #selector(newClaudeTab(_:)),
                                       keyEquivalent: "e")
        claudeTabItem.target = self
        shellMenu.addItem(claudeTabItem)
        shellMenu.addItem(withTitle: "Close Pane",
                          action: #selector(MainWindowController.closeActivePane(_:)),
                          keyEquivalent: "w")
        let closeTab = NSMenuItem(title: "Close Tab",
                                  action: #selector(MainWindowController.closeActiveTab(_:)),
                                  keyEquivalent: "w")
        closeTab.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, .shift]
        shellMenu.addItem(closeTab)

        shellMenu.addItem(.separator())

        shellMenu.addItem(withTitle: "Split Right",
                          action: #selector(MainWindowController.splitRight(_:)),
                          keyEquivalent: "d")
        let splitDownItem = NSMenuItem(title: "Split Down",
                                       action: #selector(MainWindowController.splitDown(_:)),
                                       keyEquivalent: "d")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(splitDownItem)
        let claudePaneItem = NSMenuItem(title: "New Claude Pane",
                                        action: #selector(newClaudePane(_:)),
                                        keyEquivalent: "e")
        claudePaneItem.keyEquivalentModifierMask = [.command, .shift]
        claudePaneItem.target = self
        shellMenu.addItem(claudePaneItem)

        shellMenu.addItem(.separator())

        let lastUsed = NSMenuItem(title: "Switch to Last Used Tab",
                                  action: #selector(MainWindowController.selectLastUsedTab(_:)),
                                  keyEquivalent: "\t")
        lastUsed.keyEquivalentModifierMask = [.control]
        shellMenu.addItem(lastUsed)

        shellMenu.addItem(.separator())

        // Pane navigation
        shellMenu.addItem(withTitle: "Previous Pane",
                          action: #selector(MainWindowController.selectPreviousPane(_:)),
                          keyEquivalent: "[")
        shellMenu.addItem(withTitle: "Next Pane",
                          action: #selector(MainWindowController.selectNextPane(_:)),
                          keyEquivalent: "]")
        let directionalPanes: [(String, Selector, Int)] = [
            ("Focus Pane Left",  #selector(MainWindowController.focusPaneLeft(_:)),  NSLeftArrowFunctionKey),
            ("Focus Pane Right", #selector(MainWindowController.focusPaneRight(_:)), NSRightArrowFunctionKey),
            ("Focus Pane Up",    #selector(MainWindowController.focusPaneUp(_:)),    NSUpArrowFunctionKey),
            ("Focus Pane Down",  #selector(MainWindowController.focusPaneDown(_:)),  NSDownArrowFunctionKey)
        ]
        for (title, selector, key) in directionalPanes {
            let item = NSMenuItem(title: title, action: selector,
                                  keyEquivalent: String(UnicodeScalar(key)!))
            item.keyEquivalentModifierMask = [.command, .option]
            shellMenu.addItem(item)
        }

        shellMenu.addItem(.separator())

        for number in 1...9 {
            let item = NSMenuItem(title: "Go to Tab \(number)",
                                  action: #selector(MainWindowController.selectTabByNumber(_:)),
                                  keyEquivalent: "\(number)")
            item.tag = number - 1
            shellMenu.addItem(item)
        }

        // Edit menu
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.delegate = self   // prune macOS's auto-added items (see menuNeedsUpdate)
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…",
                         action: #selector(TerminalView.openFind(_:)),
                         keyEquivalent: "f")
        editMenu.addItem(withTitle: "Find Next",
                         action: #selector(TerminalView.findNext(_:)),
                         keyEquivalent: "g")
        let findPrevious = NSMenuItem(title: "Find Previous",
                                      action: #selector(TerminalView.findPrevious(_:)),
                                      keyEquivalent: "g")
        findPrevious.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, .shift]
        editMenu.addItem(findPrevious)
        // Everything we added here is ours; menuNeedsUpdate drops the rest.
        editMenu.items.forEach { $0.tag = Self.ownMenuItemTag }

        // View menu: font size.
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(MainWindowController.increaseFontSize(_:)),
                         keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(MainWindowController.decreaseFontSize(_:)),
                         keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(MainWindowController.resetFontSize(_:)),
                         keyEquivalent: "0")

        // Window menu: ⌘M has no effect unless an item carries it.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Marks the Edit-menu items we built ourselves.
    private static let ownMenuItemTag = 0x7e1e

    /// macOS appends AutoFill / Writing Tools / Dictation / Emoji to any "Edit"
    /// menu; keep only the items we defined.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.tag != Self.ownMenuItemTag {
            menu.removeItem(item)
        }
    }
}
