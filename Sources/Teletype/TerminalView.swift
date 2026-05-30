import AppKit
import TeletypeCore

/// Draws a `TerminalEmulator`'s grid: monospaced white text on black, one line
/// per row, via AppKit/CoreText string drawing.
///
/// This is the deliberately-simple first renderer. A GPU (Metal) renderer can
/// replace `draw(_:)` later without touching the rest of the app.
final class TerminalView: NSView {
    private let emulator: TerminalEmulator
    private let font: NSFont
    private let cellHeight: CGFloat
    private let padding: CGFloat = 4

    /// Called with raw bytes to send to the shell when the user types.
    var onInput: ((Data) -> Void)?

    init(emulator: TerminalEmulator) {
        self.emulator = emulator
        self.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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
        guard let characters = event.characters, !characters.isEmpty else { return }
        onInput?(Data(characters.utf8))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        for row in 0..<emulator.rows {
            let text = emulator.line(row)
            if text.isEmpty { continue }
            let y = padding + CGFloat(row) * cellHeight
            (text as NSString).draw(at: CGPoint(x: padding, y: y), withAttributes: attributes)
        }
    }
}
