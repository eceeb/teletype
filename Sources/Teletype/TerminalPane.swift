import AppKit
import Foundation
import TeletypeCore

/// One terminal pane: a live session plus the view that draws it. A tab holds
/// one or more of these (arranged in split views).
@MainActor
final class TerminalPane {
    let session: TerminalSession
    let view: TerminalView

    /// Called when this pane's shell exits (PTY end-of-file).
    var onExit: (() -> Void)?

    private var settingsObserver: NSObjectProtocol?

    init() {
        let settings = AppSettings.store
        let session = TerminalSession(columns: 80, rows: 24)
        session.emulator.setColors(background: settings.backgroundColor,
                                   foreground: settings.foregroundColor)
        let view = TerminalView(emulator: session.emulator,
                                fontSize: CGFloat(settings.fontSize),
                                background: NSColor(settings.backgroundColor))
        self.session = session
        self.view = view

        session.onUpdate = { [weak view] in view?.needsDisplay = true }
        session.onExit = { [weak self] in self?.onExit?() }
        view.onInput = { [weak session] data in session?.write(data) }
        view.onResize = { [weak session] cols, rows in session?.resize(columns: cols, rows: rows) }

        // Live-apply settings changes.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
    }

    /// Starts a command in this pane. Defaults to the configured shell, then $SHELL.
    func start(executable: String? = nil, arguments: [String] = []) {
        let program = executable
            ?? Self.resolvedShell()
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        do {
            try session.start(executable: program, arguments: arguments, environment: environment)
        } catch {
            NSLog("teletype: failed to start \(program): \(error)")
        }
        // Sync the child's window size to the grid the view already fitted.
        session.resize(columns: session.emulator.columns, rows: session.emulator.rows)
    }

    /// The configured shell, but only if it resolves to a real executable
    /// (absolute path or found on PATH); otherwise nil so we fall back to $SHELL.
    private static func resolvedShell() -> String? {
        guard let shell = AppSettings.store.shell, !shell.isEmpty else { return nil }
        let fileManager = FileManager.default
        if shell.hasPrefix("/") {
            return fileManager.isExecutableFile(atPath: shell) ? shell : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(shell)"
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    func terminate() {
        session.terminate()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }

    private func applyAppearance() {
        let settings = AppSettings.store
        session.emulator.setColors(background: settings.backgroundColor,
                                   foreground: settings.foregroundColor)
        view.applyAppearance(fontSize: CGFloat(settings.fontSize),
                             background: NSColor(settings.backgroundColor))
    }
}
