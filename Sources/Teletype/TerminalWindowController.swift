import AppKit
import Foundation
import TeletypeCore

/// Owns one terminal: its window, the live session, and the view that draws it.
/// One instance per tab.
@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    private let session: TerminalSession
    private let terminalView: TerminalView

    /// Called when this terminal's window closes, so the app can release it.
    var onClose: ((TerminalWindowController) -> Void)?

    init() {
        let session = TerminalSession(columns: 80, rows: 24)
        let terminalView = TerminalView(emulator: session.emulator)
        self.session = session
        self.terminalView = terminalView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "teletype"
        window.tabbingIdentifier = "teletype"
        window.contentView = terminalView

        super.init(window: window)
        window.delegate = self

        session.onUpdate = { [weak terminalView] in terminalView?.needsDisplay = true }
        session.onExit = { [weak self] in self?.close() }
        terminalView.onInput = { [weak session] data in session?.write(data) }

        startShell()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func focusTerminal() {
        window?.makeFirstResponder(terminalView)
    }

    private func startShell() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        do {
            try session.start(executable: shell, environment: environment)
        } catch {
            NSLog("teletype: failed to start shell \(shell): \(error)")
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        session.terminate()
        onClose?(self)
    }
}
