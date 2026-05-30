import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Live terminal windows (tabs). Holding them keeps each one alive.
    private var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        openTerminal()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Creates a terminal window. If `existing` is given, the new window is
    /// added as a tab next to it; otherwise it opens standalone.
    @discardableResult
    func openTerminal(tabbedTo existing: NSWindow? = nil) -> TerminalWindowController {
        let controller = TerminalWindowController()
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)

        if let existing, let newWindow = controller.window {
            existing.addTabbedWindow(newWindow, ordered: .above)
        } else {
            controller.showWindow(nil)
        }
        controller.focusTerminal()
        return controller
    }

    @objc func newTab(_ sender: Any?) {
        openTerminal(tabbedTo: NSApp.keyWindow)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
        shellMenu.addItem(withTitle: "Close Tab",
                          action: #selector(NSWindow.performClose(_:)),
                          keyEquivalent: "w")

        // Window menu (enables native tab-management items)
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
