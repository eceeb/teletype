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

    /// Overrides the sidebar row label (e.g. "Claudette" for a Claude pane).
    var displayName: String?

    private var settingsObserver: NSObjectProtocol?

    /// Sidebar-row label: the last two components of the working directory,
    /// e.g. "mailing-editor/frontend".
    var title: String {
        guard let cwd = session.processWorkingDirectory() else { return "Shell" }
        let components = cwd.split(separator: "/").map(String.init)
        return components.count >= 2 ? components.suffix(2).joined(separator: "/") : (components.last ?? "Shell")
    }

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
    /// `workingDirectory` (if set) is where the shell opens — used on session restore.
    func start(executable: String? = nil, arguments: [String] = [], workingDirectory: String? = nil) {
        let program = executable
            ?? Self.resolvedShell()
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        if (program as NSString).lastPathComponent == "claude" {
            displayName = "Claudette"
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        // Launch the default shell as a *login* shell so it sources ~/.zprofile
        // (Homebrew PATH, etc.); a GUI app otherwise starts with a minimal PATH.
        let launchArgs = (executable == nil && arguments.isEmpty) ? ["-l"] : arguments
        // A fresh shell opens in the user's home dir (like any terminal); when
        // launched from /Applications the app's own cwd would otherwise be "/".
        let directory = workingDirectory ?? NSHomeDirectory()
        do {
            try session.start(executable: program, arguments: launchArgs,
                              environment: environment, workingDirectory: directory)
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
