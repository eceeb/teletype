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

    /// Whether the program enabled application cursor keys (DECCKM) — decides
    /// whether the arrow keys send ESC O x (application) or ESC [ x (normal).
    public var applicationCursorKeys: Bool { terminal.applicationCursor }

    /// The cursor's position in visible-area coordinates (row 0 = top).
    public var cursorPosition: GridPosition {
        let location = terminal.getCursorLocation()
        return GridPosition(row: location.y, column: location.x)
    }

    /// Whether the cursor should be drawn (program can hide it via DECTCEM).
    public var cursorVisible: Bool { delegate.cursorVisible }

    /// Resizes the grid to the given dimensions (SwiftTerm reflows the buffer).
    public func resize(columns: Int, rows: Int) {
        terminal.resize(cols: columns, rows: rows)
    }

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

    /// The text covered by a selection from `a` to `b` (inclusive of both
    /// cells). Rows are joined by newlines and each row's trailing whitespace
    /// is trimmed. The endpoints may be given in any order.
    public func text(from a: GridPosition, to b: GridPosition) -> String {
        let (start, end) = a <= b ? (a, b) : (b, a)
        let firstRow = max(0, start.row)
        let lastRow = min(rows - 1, end.row)
        guard firstRow <= lastRow else { return "" }

        var result: [String] = []
        for row in firstRow...lastRow {
            let fromColumn = (row == start.row) ? max(0, start.column) : 0
            let toColumn = (row == end.row) ? min(columns - 1, end.column) : (columns - 1)
            var rowText = ""
            if fromColumn <= toColumn {
                for column in fromColumn...toColumn {
                    rowText.append(cell(row: row, col: column)?.character ?? " ")
                }
            }
            while rowText.hasSuffix(" ") { rowText.removeLast() }
            result.append(rowText)
        }
        return result.joined(separator: "\n")
    }

    /// The word (a run of non-space characters) containing `position`. If the
    /// cell itself is blank, returns just that cell.
    public func wordRange(at position: GridPosition) -> (GridPosition, GridPosition) {
        let row = position.row
        func isSpace(_ column: Int) -> Bool {
            (cell(row: row, col: column)?.character ?? " ") == " "
        }
        guard !isSpace(position.column) else { return (position, position) }

        var left = position.column
        var right = position.column
        while left > 0, !isSpace(left - 1) { left -= 1 }
        while right < columns - 1, !isSpace(right + 1) { right += 1 }
        return (GridPosition(row: row, column: left), GridPosition(row: row, column: right))
    }

    /// A row's content range: column 0 to its last non-blank column.
    public func lineRange(atRow row: Int) -> (GridPosition, GridPosition) {
        var last = 0
        for column in 0..<columns where (cell(row: row, col: column)?.character ?? " ") != " " {
            last = column
        }
        return (GridPosition(row: row, column: 0), GridPosition(row: row, column: last))
    }

    /// Minimal delegate: every callback has a default no-op except `send`,
    /// which the terminal uses to reply to the host (wired up later).
    private final class NoopDelegate: TerminalDelegate {
        var cursorVisible = true
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
        func showCursor(source: Terminal) { cursorVisible = true }
        func hideCursor(source: Terminal) { cursorVisible = false }
    }
}
