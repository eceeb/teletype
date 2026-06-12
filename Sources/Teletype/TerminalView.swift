import AppKit
import TeletypeCore

/// Draws a `TerminalEmulator`'s grid cell by cell: each cell filled with its
/// background color, the glyph drawn in its foreground color (monospaced, via
/// AppKit/CoreText). A GPU (Metal) renderer can replace `draw(_:)` later without
/// touching the rest of the app.
final class TerminalView: NSView {
    private let emulator: TerminalEmulator
    private var font: NSFont
    private var boldFont: NSFont
    private var cellWidth: CGFloat
    private var cellHeight: CGFloat
    private let padding: CGFloat = 4
    private var backgroundColor: NSColor
    private var foregroundColor: NSColor

    /// Called with raw bytes to send to the shell when the user types.
    var onInput: ((Data) -> Void)?
    /// Called with the (columns, rows) that fit the view whenever that changes.
    var onResize: ((Int, Int) -> Void)?
    /// Called when this pane becomes the first responder (gains focus).
    var onFocus: (() -> Void)?
    private var lastGridSize: (cols: Int, rows: Int)?
    private var selectionStart: GridPosition?
    private var selectionEnd: GridPosition?
    private var scrollAccumulator: CGFloat = 0

    init(emulator: TerminalEmulator, fontSize: CGFloat = 13, background: NSColor = .black, foreground: NSColor = .white) {
        self.emulator = emulator
        self.backgroundColor = background
        self.foregroundColor = foreground
        let font = TerminalFont.regular(ofSize: fontSize)
        self.font = font
        self.boldFont = TerminalFont.bold(ofSize: fontSize)
        self.cellWidth = TerminalView.advance(of: font)
        self.cellHeight = ceil(font.ascender - font.descender + font.leading)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Live-applies appearance settings: rebuilds the font at the new size,
    /// updates the background, and reflows the grid.
    func applyAppearance(fontSize: CGFloat, background: NSColor, foreground: NSColor) {
        backgroundColor = background
        foregroundColor = foreground
        layer?.backgroundColor = background.cgColor
        let font = TerminalFont.regular(ofSize: fontSize)
        self.font = font
        boldFont = TerminalFont.bold(ofSize: fontSize)
        cellWidth = TerminalView.advance(of: font)
        cellHeight = ceil(font.ascender - font.descender + font.leading)
        lastGridSize = nil          // force a reflow at the new cell size
        reportGridSizeIfChanged()
        needsDisplay = true
    }

    // Draw rows from the top down.
    override var isFlipped: Bool { true }

    // MARK: - Keyboard input

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onFocus?()
        return super.becomeFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        // Let ⌘-shortcuts (New Tab, Close, Quit, …) go to the menu instead of
        // being typed into the shell.
        guard !event.modifierFlags.contains(.command) else { return }
        if emulator.isScrolledBack {   // typing jumps back to the live view
            emulator.scrollToBottom()
            needsDisplay = true
        }
        if let special = event.specialKey, let sequence = escapeSequence(for: special) {
            onInput?(Data(sequence.utf8))
            return
        }
        guard let characters = event.characters, !characters.isEmpty else { return }
        onInput?(Data(characters.utf8))
    }

    /// Maps arrow/navigation keys to terminal escape sequences. Returns nil for
    /// keys (Return, Tab, Backspace, …) that already send the correct character.
    private func escapeSequence(for key: NSEvent.SpecialKey) -> String? {
        let app = emulator.applicationCursorKeys
        switch key {
        case .upArrow:       return app ? "\u{1b}OA" : "\u{1b}[A"
        case .downArrow:     return app ? "\u{1b}OB" : "\u{1b}[B"
        case .rightArrow:    return app ? "\u{1b}OC" : "\u{1b}[C"
        case .leftArrow:     return app ? "\u{1b}OD" : "\u{1b}[D"
        case .home:          return "\u{1b}[H"
        case .end:           return "\u{1b}[F"
        case .pageUp:        return "\u{1b}[5~"
        case .pageDown:      return "\u{1b}[6~"
        case .deleteForward: return "\u{1b}[3~"
        default:             return nil
        }
    }

    /// Cmd-V: send the clipboard's text to the shell.
    @objc func paste(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        onInput?(Data(string.utf8))
    }

    // MARK: - Mouse selection

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)   // clicking a pane focuses it
        let position = gridPosition(at: convert(event.locationInWindow, from: nil))
        switch event.clickCount {
        case 2:   // double-click selects the word
            let (start, end) = emulator.wordRange(at: position)
            selectionStart = start
            selectionEnd = end
        case 3:   // triple-click selects the line
            let (start, end) = emulator.lineRange(atRow: position.row)
            selectionStart = start
            selectionEnd = end
        default:
            selectionStart = position
            selectionEnd = position
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        selectionEnd = gridPosition(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // A plain single click (no drag, no double/triple) clears the selection.
        if event.clickCount <= 1, selectionStart == selectionEnd {
            selectionStart = nil
            selectionEnd = nil
            needsDisplay = true
        }
    }

    // MARK: - Scrolling

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        let lines = Int(scrollAccumulator / cellHeight)
        guard lines != 0 else { return }
        scrollAccumulator -= CGFloat(lines) * cellHeight
        emulator.scroll(lines: lines)   // positive = toward older output
        needsDisplay = true
    }

    /// Cmd-C: copy the selected text to the clipboard.
    @objc func copy(_ sender: Any?) {
        guard let start = selectionStart, let end = selectionEnd, start != end else { return }
        let text = emulator.text(from: start, to: end)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func gridPosition(at point: NSPoint) -> GridPosition {
        let column = Int((point.x - padding) / cellWidth)
        let row = Int((point.y - padding) / cellHeight)
        return GridPosition(row: max(0, min(emulator.rows - 1, row)),
                            column: max(0, min(emulator.columns - 1, column)))
    }

    private func isSelected(row: Int, column: Int) -> Bool {
        guard let s = selectionStart, let e = selectionEnd, s != e else { return false }
        let (start, end) = s <= e ? (s, e) : (e, s)
        let position = GridPosition(row: row, column: column)
        return position >= start && position <= end
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportGridSizeIfChanged()
    }

    private func reportGridSizeIfChanged() {
        let cols = max(1, Int((bounds.width - 2 * padding) / cellWidth))
        let rows = max(1, Int((bounds.height - 2 * padding) / cellHeight))
        guard lastGridSize?.cols != cols || lastGridSize?.rows != rows else { return }
        lastGridSize = (cols, rows)
        onResize?(cols, rows)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()

        for row in 0..<emulator.rows {
            // Round cell edges to whole pixels so adjacent backgrounds tile
            // seamlessly — a fractional cellWidth/Height otherwise leaves thin
            // gridlines between cells (very visible on a full-screen background).
            let y0 = (padding + CGFloat(row) * cellHeight).rounded()
            let y1 = (padding + CGFloat(row + 1) * cellHeight).rounded()
            for col in 0..<emulator.columns {
                guard let cell = emulator.cell(row: row, col: col) else { continue }
                let span = cell.width == 2 ? 2 : 1
                let x0 = (padding + CGFloat(col) * cellWidth).rounded()
                let x1 = (padding + CGFloat(col + span) * cellWidth).rounded()
                let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

                nsColor(cell.background).setFill()
                rect.fill()

                if isSelected(row: row, column: col) {
                    foregroundColor.withAlphaComponent(0.25).setFill()
                    rect.fill()
                }

                // Skip blanks and the trailing half of a wide glyph (width 0).
                if cell.width > 0, cell.character != " " {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: cell.bold ? boldFont : font,
                        .foregroundColor: nsColor(legibleForeground(cell.foreground, on: cell.background))
                    ]
                    if cell.italic { attributes[.obliqueness] = 0.2 }
                    if cell.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    (String(cell.character) as NSString).draw(at: rect.origin, withAttributes: attributes)
                }
            }
        }

        drawCursor()
    }

    private func drawCursor() {
        guard emulator.cursorVisible, !emulator.isScrolledBack else { return }
        let cursor = emulator.cursorPosition
        guard cursor.row >= 0, cursor.row < emulator.rows,
              cursor.column >= 0, cursor.column < emulator.columns else { return }
        let rect = CGRect(
            x: padding + CGFloat(cursor.column) * cellWidth,
            y: padding + CGFloat(cursor.row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        if window?.firstResponder === self {
            foregroundColor.withAlphaComponent(0.6).setFill()
            rect.fill()
        } else {
            foregroundColor.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// One monospace cell's advance, in whole pixels. Measured from a real glyph
    /// ("0") rather than `maximumAdvancement`, which a Nerd Font inflates with its
    /// wide icon glyphs (that made every cell too wide). Rounding to an integer
    /// keeps columns evenly spaced and lets cell backgrounds tile without seams.
    private static func advance(of font: NSFont) -> CGFloat {
        let width = ("0" as NSString).size(withAttributes: [.font: font]).width
        return max(1, width.rounded())
    }

    /// Keeps glyphs legible when a program draws the foreground in (nearly) the
    /// background color. asciiquarium's castle, for example, is BLACK on a black
    /// background and relies on terminals showing it as a faint gray. Only nudges
    /// when the two are almost identical, so normal colors stay untouched.
    private func legibleForeground(_ fg: TermColor, on bg: TermColor) -> TermColor {
        let dr = Int(fg.red) - Int(bg.red)
        let dg = Int(fg.green) - Int(bg.green)
        let db = Int(fg.blue) - Int(bg.blue)
        guard dr * dr + dg * dg + db * db < 30 * 30 else { return fg }
        let bgLuminance = 0.299 * Double(bg.red) + 0.587 * Double(bg.green) + 0.114 * Double(bg.blue)
        let shift = 78
        func nudge(_ value: UInt8) -> UInt8 {
            bgLuminance < 128 ? UInt8(min(255, Int(value) + shift))
                              : UInt8(max(0, Int(value) - shift))
        }
        return TermColor(red: nudge(bg.red), green: nudge(bg.green), blue: nudge(bg.blue))
    }

    private func nsColor(_ color: TermColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1)
    }
}
