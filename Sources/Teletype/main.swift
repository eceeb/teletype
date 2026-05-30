import AppKit
import Foundation
import TeletypeCore

/// Minimal app shell: one window hosting the terminal view.
/// (Static text for now — live PTY output is the next step, 3c.)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "teletype"
        window.center()

        let emulator = TerminalEmulator(columns: 80, rows: 24)
        emulator.feed(Data("teletype — step 3b\r\nthe grid is drawn from the emulator\r\n$ ".utf8))

        let terminalView = TerminalView(emulator: emulator)
        window.contentView = terminalView

        window.makeKeyAndOrderFront(nil)
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
