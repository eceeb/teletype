import Foundation
import SwiftTerm

/// Turns a raw byte stream (e.g. PTY output) into a character grid by driving
/// SwiftTerm's escape-sequence parser.
///
/// SwiftTerm sits *behind* this type so the rest of the app talks only to our
/// own interface — we can refine or replace the parser later without touching
/// callers.
public final class TerminalEmulator {
    private let terminal: Terminal
    private let delegate: NoopDelegate

    public init(columns: Int = 80, rows: Int = 24) {
        delegate = NoopDelegate()
        terminal = Terminal(delegate: delegate)
        terminal.resize(cols: columns, rows: rows)
    }

    /// Feeds raw output bytes into the parser, updating the grid.
    public func feed(_ data: Data) {
        terminal.feed(byteArray: [UInt8](data))
    }

    /// The visible text of a row (0 = top of the visible area), trailing
    /// blanks trimmed. Empty string if the row is out of bounds.
    public func line(_ row: Int) -> String {
        terminal.getLine(row: row)?.translateToString(trimRight: true) ?? ""
    }

    /// Number of rows in the grid.
    public var rows: Int { terminal.rows }

    /// Number of columns in the grid.
    public var columns: Int { terminal.cols }

    /// Minimal delegate: every callback has a default no-op except `send`,
    /// which the terminal uses to reply to the host (wired up later).
    private final class NoopDelegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }
}
