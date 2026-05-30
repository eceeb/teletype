import AppKit
import Foundation
import TeletypeCore

/// Minimal app shell: one window hosting a live, interactive terminal session.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var session: TerminalSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "teletype"
        window.center()

        // Live session: shell output streams into the grid; redraw on update.
        let session = TerminalSession(columns: 80, rows: 24)
        let terminalView = TerminalView(emulator: session.emulator)
        session.onUpdate = { [weak terminalView] in
            terminalView?.needsDisplay = true
        }
        session.onExit = { NSApp.terminate(nil) }

        // Keyboard: typed bytes go straight to the shell, which echoes them
        // back via the PTY so they appear on screen.
        terminalView.onInput = { [weak session] data in
            session?.write(data)
        }

        window.contentView = terminalView

        // Shell is freely choosable: default to the user's login shell ($SHELL).
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        do {
            try session.start(executable: shell, environment: environment)
        } catch {
            NSLog("teletype: failed to start shell \(shell): \(error)")
        }
        self.session = session

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminalView)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
