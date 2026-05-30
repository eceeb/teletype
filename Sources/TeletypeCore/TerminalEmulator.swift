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
    private let palette = TerminalPalette.standard

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

    /// The fully-resolved cell at the given position (row 0 / col 0 = top-left
    /// of the visible area): character, colors (inverse applied), width and
    /// styling. Returns nil if out of bounds.
    public func cell(row: Int, col: Int) -> TerminalCell? {
        guard let data = terminal.getCharData(col: col, row: row) else { return nil }
        let attribute = data.attribute
        var foreground = palette.color(for: attribute.fg, isForeground: true)
        var background = palette.color(for: attribute.bg, isForeground: false)
        if attribute.style.contains(.inverse) {
            swap(&foreground, &background)
        }
        let raw = data.getCharacter()
        let character: Character = (raw.unicodeScalars.first?.value ?? 0) == 0 ? " " : raw
        return TerminalCell(
            character: character,
            foreground: foreground,
            background: background,
            width: Int(data.width),
            bold: attribute.style.contains(.bold),
            italic: attribute.style.contains(.italic),
            underline: attribute.style.contains(.underline)
        )
    }

    /// Minimal delegate: every callback has a default no-op except `send`,
    /// which the terminal uses to reply to the host (wired up later).
    private final class NoopDelegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }
}
