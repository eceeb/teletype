import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainController: MainWindowController?
    private var settingsWindow: NSWindow?
    private var shortcutsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        let controller = MainWindowController()
        controller.showWindow(nil)
        mainController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Claude (resolve, then route into the main window)

    @objc func newClaudeTab(_ sender: Any?) {
        withClaude { mainController?.newTab(executable: $0) }
    }

    @objc func newClaudePane(_ sender: Any?) {
        withClaude { mainController?.splitActivePane(vertical: true, executable: $0) }
    }

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

    private static func resolveExecutable(named name: String) -> String? {
        let pathVariable = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for directory in pathVariable.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
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
            window.setContentSize(NSSize(width: 380, height: 220))
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
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
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
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")

        NSApp.mainMenu = mainMenu
    }
}
