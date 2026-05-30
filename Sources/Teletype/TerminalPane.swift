import AppKit
import Foundation
import TeletypeCore

/// One terminal pane: a live session plus the view that draws it. A tab holds
/// one or more of these (arranged in split views once splitting lands).
@MainActor
final class TerminalPane {
    let session: TerminalSession
    let view: TerminalView

    /// Called when this pane's shell exits (PTY end-of-file).
    var onExit: (() -> Void)?

    init() {
        let session = TerminalSession(columns: 80, rows: 24)
        let view = TerminalView(emulator: session.emulator)
        self.session = session
        self.view = view

        session.onUpdate = { [weak view] in view?.needsDisplay = true }
        session.onExit = { [weak self] in self?.onExit?() }
        view.onInput = { [weak session] data in session?.write(data) }
        view.onResize = { [weak session] cols, rows in session?.resize(columns: cols, rows: rows) }
    }

    /// Starts the user's shell ($SHELL, default zsh) in this pane.
    func start() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        do {
            try session.start(executable: shell, environment: environment)
        } catch {
            NSLog("teletype: failed to start shell \(shell): \(error)")
        }
        // Sync the child's window size to the grid the view already fitted.
        session.resize(columns: session.emulator.columns, rows: session.emulator.rows)
    }

    func terminate() {
        session.terminate()
    }
}
