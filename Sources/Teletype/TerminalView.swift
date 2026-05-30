import AppKit
import TeletypeCore

/// Draws a `TerminalEmulator`'s grid cell by cell: each cell filled with its
/// background color, the glyph drawn in its foreground color (monospaced, via
/// AppKit/CoreText). A GPU (Metal) renderer can replace `draw(_:)` later without
/// touching the rest of the app.
final class TerminalView: NSView {
    private let emulator: TerminalEmulator
    private let font: NSFont
    private let boldFont: NSFont
    private let cellWidth: CGFloat
    private let cellHeight: CGFloat
    private let padding: CGFloat = 4

    /// Called with raw bytes to send to the shell when the user types.
    var onInput: ((Data) -> Void)?
    /// Called with the (columns, rows) that fit the view whenever that changes.
    var onResize: ((Int, Int) -> Void)?
    private var lastGridSize: (cols: Int, rows: Int)?

    init(emulator: TerminalEmulator) {
        self.emulator = emulator
        let font = TerminalFont.regular
        self.font = font
        self.boldFont = TerminalFont.bold
        self.cellWidth = font.maximumAdvancement.width
        self.cellHeight = ceil(font.ascender - font.descender + font.leading)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Draw rows from the top down.
    override var isFlipped: Bool { true }

    // MARK: - Keyboard input

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Let ⌘-shortcuts (New Tab, Close, Quit, …) go to the menu instead of
        // being typed into the shell.
        guard !event.modifierFlags.contains(.command) else { return }
        guard let characters = event.characters, !characters.isEmpty else { return }
        onInput?(Data(characters.utf8))
    }

    /// Cmd-V: send the clipboard's text to the shell.
    @objc func paste(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        onInput?(Data(string.utf8))
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
        NSColor.black.setFill()
        bounds.fill()

        for row in 0..<emulator.rows {
            for col in 0..<emulator.columns {
                guard let cell = emulator.cell(row: row, col: col) else { continue }
                let span = cell.width == 2 ? 2 : 1
                let rect = CGRect(
                    x: padding + CGFloat(col) * cellWidth,
                    y: padding + CGFloat(row) * cellHeight,
                    width: cellWidth * CGFloat(span),
                    height: cellHeight
                )

                nsColor(cell.background).setFill()
                rect.fill()

                // Skip blanks and the trailing half of a wide glyph (width 0).
                if cell.width > 0, cell.character != " " {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: cell.bold ? boldFont : font,
                        .foregroundColor: nsColor(cell.foreground)
                    ]
                    if cell.italic { attributes[.obliqueness] = 0.2 }
                    if cell.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    (String(cell.character) as NSString).draw(at: rect.origin, withAttributes: attributes)
                }
            }
        }
    }

    private func nsColor(_ color: TermColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1)
    }
}
