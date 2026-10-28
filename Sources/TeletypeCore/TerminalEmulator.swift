import Foundation
import SwiftTerm

/// How the cursor is drawn. Programs set this with DECSCUSR — vim switches to
/// a bar in insert mode and back to a block in normal mode.
public enum CursorShape: Sendable {
    case block, underline, bar
}

public struct TerminalCursorStyle: Equatable, Sendable {
    public let shape: CursorShape
    public let blinks: Bool

    public init(shape: CursorShape, blinks: Bool) {
        self.shape = shape
        self.blinks = blinks
    }
}

/// Turns a raw byte stream (e.g. PTY output) into a character grid by driving
/// SwiftTerm's escape-sequence parser.
///
/// SwiftTerm sits *behind* this type so the rest of the app talks only to our
/// own interface — we can refine or replace the parser later without touching
/// callers.
public final class TerminalEmulator {
    private let terminal: Terminal
    private let delegate: NoopDelegate
    private var palette = TerminalPalette.standard
    /// Shadows SwiftTerm's `yBase` (the bottom scroll bound, not public): the
    /// display offset of the live, newest screen. Re-anchored from yDisp on output.
    private var liveBottom = 0
    /// Whether the user scrolled up from the live bottom. Tracked explicitly, not
    /// derived from `yDisp < liveBottom`: deriving it meant a drifted liveBottom
    /// (after a silent yBase move) could wedge the view as permanently scrolled
    /// back, which broke the cursor and the screen after a resize/clear.
    private var userScrolledBack = false

    public init(columns: Int = 80, rows: Int = 24, scrollback: Int = 10_000) {
        delegate = NoopDelegate()
        // Start both sides on the same style. SwiftTerm defaults to a blinking
        // block and only reports *changes*, so without this a program asking for
        // "blinking block" (DECSCUSR 1) would be silently dropped while we drew
        // a steady one.
        terminal = Terminal(delegate: delegate,
                            options: TerminalOptions(cursorStyle: .steadyBlock,
                                                     scrollback: max(0, scrollback)))
        terminal.resize(cols: columns, rows: rows)
        // Forward terminal→program replies to the PTY.
        delegate.onSend = { [weak self] data in self?.onRespond?(Data(data)) }
    }

    /// Changes how many scrollback lines are kept, applied live to this pane.
    public func setScrollback(_ lines: Int) {
        terminal.changeScrollback(max(0, lines))
    }

    /// Feeds raw output bytes into the parser, updating the grid.
    public func feed(_ data: Data) {
        let wasAlternate = terminal.isCurrentBufferAlternate
        let previousBottom = liveBottom

        terminal.feed(byteArray: [UInt8](data))
        // Output returns to the live bottom: SwiftTerm pins yDisp to yBase on
        // output (it never sees a user scroll), so yDisp is now the true bottom.
        // Re-anchor to it — this self-heals liveBottom after any silent yBase move
        // (clear-scrollback ED 3, resize, alt-screen) and matches "output scrolls
        // to the bottom".
        liveBottom = terminal.buffer.yDisp
        userScrolledBack = false

        // Buffer-absolute row numbers only change meaning in two cases: the
        // screen was swapped, or the bottom moved *backwards* because rows were
        // dropped (ED 3). Growing output keeps every existing row where it was.
        if wasAlternate != terminal.isCurrentBufferAlternate || liveBottom < previousBottom {
            onBufferInvalidated?()
        }
    }

    /// The rows that changed since this was last called, as a half-open range of
    /// visible rows, or nil when nothing changed. Calling it clears the range,
    /// so the renderer can repaint just that band instead of the whole grid.
    public func takeDirtyRows() -> Range<Int>? {
        guard let range = terminal.getUpdateRange() else { return nil }
        terminal.clearUpdateRange()
        let start = max(0, range.startY)
        let end = min(rows, range.endY + 1)      // SwiftTerm's endY is inclusive
        return start < end ? start..<end : nil
    }

    /// How the running program wants the cursor drawn (DECSCUSR).
    public var cursorStyle: TerminalCursorStyle { delegate.cursorStyle }

    /// Colors a program set with OSC 10/11/12, if it did. A theme switcher in
    /// a shell prompt sends these; nil means "the user's own setting stands".
    public var programForeground: TermColor? { delegate.programForeground }
    public var programBackground: TermColor? { delegate.programBackground }
    public var programCursorColor: TermColor? { delegate.programCursorColor }

    /// Called when a program changed any of the colors above.
    public var onColorsChanged: (() -> Void)? {
        get { delegate.onColorsChanged }
        set { delegate.onColorsChanged = newValue }
    }

    /// Called when a program puts text on the clipboard with OSC 52 — what tmux
    /// and vim use to copy out of an SSH session.
    public var onClipboardCopy: ((String) -> Void)? {
        get { delegate.onClipboardCopy }
        set { delegate.onClipboardCopy = newValue }
    }

    /// Called when a program raises a notification (OSC 9) with title and body.
    public var onNotify: ((String, String) -> Void)? {
        get { delegate.onNotify }
        set { delegate.onNotify = newValue }
    }

    /// Called when a program rings the bell (BEL).
    public var onBell: (() -> Void)? {
        get { delegate.onBell }
        set { delegate.onBell = newValue }
    }

    /// Called when the program changes the cursor style.
    public var onCursorStyleChange: (() -> Void)? {
        get { delegate.onCursorStyleChange }
        set { delegate.onCursorStyleChange = newValue }
    }

    /// The whole of what has been written, for Select All: from the first row to
    /// the end of the last non-empty one. Nil when the terminal is still blank.
    public func contentRange() -> (start: GridPosition, end: GridPosition)? {
        let lines = bufferLines()
        guard let lastUsed = lines.lastIndex(where: { !$0.isEmpty }) else { return nil }
        return (GridPosition(row: 0, column: 0),
                GridPosition(row: lastUsed, column: max(0, lines[lastUsed].count - 1)))
    }

    /// Every line in the buffer — scrollback first, then the visible screen —
    /// indexed by buffer-absolute row. This is what search runs over.
    ///
    /// SwiftTerm only exposes cells through the viewport, so the rows are read
    /// by parking it; the viewport is put back before returning.
    public func bufferLines() -> [String] {
        let savedOffset = terminal.buffer.yDisp
        defer { terminal.buffer.yDisp = savedOffset }

        var lines: [String] = []
        lines.reserveCapacity(liveBottom + rows)
        for absoluteRow in 0..<(liveBottom + rows) {
            // getLine(row:) reads lines[row + yDisp], so park the viewport at or
            // before the wanted row and index the rest from there.
            let offset = min(absoluteRow, liveBottom)
            terminal.buffer.yDisp = offset
            lines.append(terminal.getLine(row: absoluteRow - offset)?
                .translateToString(trimRight: true) ?? "")
        }
        return lines
    }

    /// Scrolls so that `absoluteRow` is visible, centering it when there is room.
    public func scrollToReveal(absoluteRow: Int) {
        let centered = absoluteRow - rows / 2
        let target = max(0, min(liveBottom, centered))
        terminal.buffer.yDisp = target
        userScrolledBack = target < liveBottom
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

    /// The title the program set (OSC 0/2) — often the shell's command or cwd.
    public var title: String { delegate.title }
    /// The working directory reported via OSC 7, if any.
    public var currentDirectory: String? { terminal.hostCurrentDirectory }
    /// Called when the title or working directory changes.
    public var onTitleChange: (() -> Void)? {
        get { delegate.onChange }
        set { delegate.onChange = newValue }
    }
    /// Called when the terminal must reply to the program (cursor-position
    /// report, device attributes, …). The reply is written to the PTY as input —
    /// curses / full-screen apps rely on these answers to render correctly.
    public var onRespond: ((Data) -> Void)?
    /// Called when buffer-absolute rows stop meaning what they did — the screen
    /// was swapped (a pager opened or quit) or the scrollback was dropped.
    /// Anything anchored to those rows, i.e. a selection, is stale afterwards.
    public var onBufferInvalidated: (() -> Void)?

    /// Scrolls the viewport by `lines` (positive = toward older output).
    public func scroll(lines: Int) {
        let target = max(0, min(liveBottom, terminal.buffer.yDisp - lines))
        terminal.buffer.yDisp = target
        userScrolledBack = target < liveBottom
    }

    /// Jumps the viewport back to the live (newest) output.
    public func scrollToBottom() {
        terminal.buffer.yDisp = liveBottom
        userScrolledBack = false
    }

    /// Whether the viewport is scrolled away from the live bottom. The alternate
    /// screen never scrolls back, so only the normal buffer can be.
    public var isScrolledBack: Bool {
        !terminal.isCurrentBufferAlternate && userScrolledBack
    }

    /// Where the viewport sits in the buffer. A visible row `r` is buffer row
    /// `r + scrollOffset`; the view anchors selections that way so they stay on
    /// the same text while it scrolls.
    public var scrollOffset: Int { terminal.buffer.yDisp }

    /// Whether a full-screen program (pager, editor, htop) owns the screen.
    /// There is no scrollback there, so the wheel must drive the program.
    public var isAlternateScreen: Bool { terminal.isCurrentBufferAlternate }

    /// Which mouse events the running program asked to be told about. While
    /// this is `.off` the mouse belongs to the terminal (text selection).
    public var mouseTracking: MouseTracking {
        switch terminal.mouseMode {
        case .off:                 return .off
        case .x10:                 return .pressOnly
        case .vt200:               return .pressAndRelease
        case .buttonEventTracking: return .withDrag
        case .anyEvent:            return .anyMotion
        @unknown default:          return .off
        }
    }

    /// Reports a mouse event to the program, if it wants that kind. `column`
    /// and `row` are 0-based visible-grid coordinates; SwiftTerm picks the wire
    /// format the program negotiated (X10, SGR, urxvt, utf8).
    public func sendMouse(_ kind: MouseEventKind, button: MouseButton,
                          modifiers: KeyModifiers, column: Int, row: Int) {
        guard MouseReport.shouldReport(kind, tracking: mouseTracking) else { return }
        terminal.sendEvent(
            buttonFlags: MouseReport.buttonFlags(kind, button: button, modifiers: modifiers),
            x: column, y: row)
    }

    /// Whether the program enabled bracketed paste (DECSET 2004). Pasted text
    /// then has to be wrapped so the shell takes it as one literal block
    /// instead of as keystrokes — otherwise every newline runs immediately.
    public var bracketedPaste: Bool { terminal.bracketedPasteMode }

    /// Sets the default foreground/background colors (the theme). ANSI-colored
    /// text keeps its own colors.
    public func setColors(background: TermColor, foreground: TermColor, ansi16: [TermColor]? = nil) {
        palette = TerminalPalette(defaultForeground: foreground, defaultBackground: background, ansi16: ansi16)
    }

    /// Resizes the grid to the given dimensions (SwiftTerm reflows the buffer).
    public func resize(columns: Int, rows: Int) {
        let wasScrolledBack = userScrolledBack
        terminal.resize(cols: columns, rows: rows)
        // A resize while following the live output keeps us there; re-anchor.
        // (If scrolled back, the next output re-anchors — see feed.)
        if !wasScrolledBack { liveBottom = terminal.buffer.yDisp }
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
        // Via the terminal, not CharData.getCharacter(): a cell can hold a
        // pointer into a grapheme-cluster table rather than a bare rune, and
        // only the terminal can resolve that. Reading it the other way turned
        // every emoji — anything outside the BMP — into a blank.
        let raw = terminal.getCharacter(for: data)
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

        var collected: [(text: String, isContinuation: Bool)] = []
        for row in firstRow...lastRow {
            let fromColumn = (row == start.row) ? max(0, start.column) : 0
            let toColumn = (row == end.row) ? min(columns - 1, end.column) : (columns - 1)
            collected.append((rowText(row: row, from: fromColumn, through: toColumn),
                              terminal.getLine(row: row)?.isWrapped ?? false))
        }
        return joined(collected)
    }

    /// One row's characters, skipping the width-0 placeholder that follows a wide
    /// glyph — appending it would put a stray space after every emoji/CJK char.
    private func rowText(row: Int, from fromColumn: Int, through toColumn: Int) -> String {
        guard fromColumn <= toColumn else { return "" }
        var text = ""
        for column in fromColumn...toColumn {
            guard let cell = cell(row: row, col: column) else { continue }
            if cell.width == 0 { continue }
            text.append(cell.character)
        }
        return text
    }

    /// Joins rows, honoring soft wraps: a row flagged `isWrapped` is the
    /// continuation of the one above, so it must not get a newline — otherwise a
    /// long command or URL comes back cut in half. Only rows that really end are
    /// trimmed of trailing blanks.
    private func joined(_ rows: [(text: String, isContinuation: Bool)]) -> String {
        var result = ""
        for (index, row) in rows.enumerated() {
            var text = row.text
            let continuesBelow = index + 1 < rows.count && rows[index + 1].isContinuation
            if !continuesBelow {
                while text.hasSuffix(" ") { text.removeLast() }
            }
            if index > 0, !row.isContinuation { result += "\n" }
            result += text
        }
        return result
    }

    /// Like `text(from:to:)`, but rows are buffer-absolute (a visible row plus
    /// `scrollOffset`). Needed for a selection made while scrolling: parts of it
    /// are off-screen, and the viewport-relative version would clip them.
    public func text(fromAbsolute a: GridPosition, toAbsolute b: GridPosition) -> String {
        let (start, end) = a <= b ? (a, b) : (b, a)
        let firstRow = max(0, start.row)
        guard firstRow <= end.row else { return "" }

        // SwiftTerm only exposes cells through the viewport, so walk the rows by
        // parking the viewport on each one. Restored before returning.
        let savedOffset = terminal.buffer.yDisp
        defer { terminal.buffer.yDisp = savedOffset }

        var collected: [(text: String, isContinuation: Bool)] = []
        for absoluteRow in firstRow...end.row {
            terminal.buffer.yDisp = absoluteRow       // row now sits at visible row 0
            let fromColumn = (absoluteRow == start.row) ? max(0, start.column) : 0
            let toColumn = (absoluteRow == end.row) ? min(columns - 1, end.column) : (columns - 1)
            collected.append((rowText(row: 0, from: fromColumn, through: toColumn),
                              terminal.getLine(row: 0)?.isWrapped ?? false))
        }
        return joined(collected)
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
        var title = ""
        var cursorStyle = TerminalCursorStyle(shape: .block, blinks: false)
        var onCursorStyleChange: (() -> Void)?
        var onBell: (() -> Void)?
        var programForeground: TermColor?
        var programBackground: TermColor?
        var programCursorColor: TermColor?
        var onColorsChanged: (() -> Void)?
        var onClipboardCopy: ((String) -> Void)?
        var onNotify: ((String, String) -> Void)?
        var onChange: (() -> Void)?
        var onSend: ((ArraySlice<UInt8>) -> Void)?
        func send(source: Terminal, data: ArraySlice<UInt8>) { onSend?(data) }
        func showCursor(source: Terminal) { cursorVisible = true }
        func hideCursor(source: Terminal) { cursorVisible = false }
        func setTerminalTitle(source: Terminal, title: String) {
            self.title = title
            onChange?()
        }
        func hostCurrentDirectoryUpdated(source: Terminal) { onChange?() }
        func bell(source: Terminal) { onBell?() }

        // SwiftTerm's Color is 16 bits per channel; ours is 8.
        private func term(_ color: SwiftTerm.Color) -> TermColor {
            TermColor(red: UInt8(color.red >> 8),
                      green: UInt8(color.green >> 8),
                      blue: UInt8(color.blue >> 8))
        }

        // SwiftTerm reports OSC 10/11 through two paths, so each sequence
        // arrives twice; only a real change is worth a repaint.
        //
        // Each of these assigns first and calls back afterwards, deliberately
        // not through a shared `inout` helper: the handler reads these same
        // properties to repaint, and an inout parameter holds exclusive access
        // across the call — which trapped at runtime.
        func setForegroundColor(source: Terminal, color: SwiftTerm.Color) {
            let new = term(color)
            guard programForeground != new else { return }
            programForeground = new
            onColorsChanged?()
        }

        func setBackgroundColor(source: Terminal, color: SwiftTerm.Color) {
            let new = term(color)
            guard programBackground != new else { return }
            programBackground = new
            onColorsChanged?()
        }

        func setCursorColor(source: Terminal, color: SwiftTerm.Color?) {
            let new = color.map(term)
            guard programCursorColor != new else { return }
            programCursorColor = new
            onColorsChanged?()
        }

        func clipboardCopy(source: Terminal, content: Data) {
            onClipboardCopy?(String(decoding: content, as: UTF8.self))
        }

        /// Deliberately never answers. A program that could *read* the clipboard
        /// would be handing itself whatever the user last copied — a password,
        /// say — with no way for them to notice.
        func clipboardRead(source: Terminal) -> Data? { nil }

        func notify(source: Terminal, title: String, body: String) {
            onNotify?(title, body)
        }
        func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
            switch newStyle {
            case .blinkBlock:      cursorStyle = .init(shape: .block, blinks: true)
            case .steadyBlock:     cursorStyle = .init(shape: .block, blinks: false)
            case .blinkUnderline:  cursorStyle = .init(shape: .underline, blinks: true)
            case .steadyUnderline: cursorStyle = .init(shape: .underline, blinks: false)
            case .blinkBar:        cursorStyle = .init(shape: .bar, blinks: true)
            case .steadyBar:       cursorStyle = .init(shape: .bar, blinks: false)
            }
            onCursorStyleChange?()
        }
    }
}
