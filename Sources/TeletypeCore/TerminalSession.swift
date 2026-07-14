import Foundation

/// Connects a live child process (the shell) to a `TerminalEmulator`: it reads
/// the PTY's output as it arrives, feeds it into the grid, and notifies a
/// callback so the UI can redraw.
///
/// Marked `@MainActor` so its state (PTY + emulator) is only ever touched on the
/// main thread — the same thread the view draws on — keeping the grid race-free
/// without locks. The read source is scheduled on the main queue, which the
/// AppKit run loop drains.
@MainActor
public final class TerminalSession {
    public let emulator: TerminalEmulator
    private let pty = PTYProcess()
    private var readSource: DispatchSourceRead?

    /// Called after new output has been fed into the grid.
    public var onUpdate: (() -> Void)?
    /// Called once the shell has exited (PTY reached end-of-file).
    public var onExit: (() -> Void)?

    public init(columns: Int = 80, rows: Int = 24, scrollback: Int = 10_000) {
        emulator = TerminalEmulator(columns: columns, rows: rows, scrollback: scrollback)
        // Terminal replies (cursor-position reports, device attributes, …) are
        // sent back to the program as input — curses apps need these answers.
        emulator.onRespond = { [weak self] data in self?.write(data) }
    }

    /// Starts the shell and begins streaming its output into the grid.
    public func start(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: String? = nil
    ) throws {
        try pty.start(executable: executable, arguments: arguments,
                      environment: environment, workingDirectory: workingDirectory)
        // Give the PTY a sane size up front (matching the emulator's default grid)
        // so a program that runs at shell startup — e.g. a login-time prompt —
        // sees a real width. Otherwise it starts at the kernel default of 0×0 and
        // its output wraps to a sliver until the view reports its real size.
        pty.setWindowSize(columns: emulator.columns, rows: emulator.rows)

        let source = DispatchSource.makeReadSource(fileDescriptor: pty.masterFD, queue: .main)
        source.setEventHandler { [weak self] in
            // The handler runs on the main queue, so it is safe to touch our
            // main-actor state synchronously.
            MainActor.assumeIsolated {
                guard let self else { return }
                let chunk = self.pty.read(timeoutMillis: 0)
                if chunk.isEmpty {
                    // Readable but no data → the shell exited (EOF).
                    self.handleExit()
                    return
                }
                self.emulator.feed(chunk)
                self.onUpdate?()
            }
        }
        source.resume()
        readSource = source
    }

    /// Sends input (e.g. keystrokes) to the shell.
    public func write(_ data: Data) {
        pty.write(data)
    }

    /// Resizes the grid and informs the child process of the new size.
    public func resize(columns: Int, rows: Int) {
        emulator.resize(columns: columns, rows: rows)
        pty.setWindowSize(columns: columns, rows: rows)
    }

    /// The shell's current working directory (queried from the OS).
    public func processWorkingDirectory() -> String? {
        pty.workingDirectory()
    }

    /// The foreground command running on the PTY (nil when it's just the shell).
    public func foregroundProcessName() -> String? {
        pty.foregroundProcessName()
    }

    /// Stops reading and asks the shell to terminate.
    public func terminate() {
        readSource?.cancel()
        readSource = nil
        pty.terminate()
    }

    private func handleExit() {
        readSource?.cancel()
        readSource = nil
        onExit?()
    }
}
