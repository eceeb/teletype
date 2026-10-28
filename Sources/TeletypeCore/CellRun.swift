/// A stretch of neighbouring cells in one row that share their text
/// attributes, so the renderer can draw them in a single CoreText call instead
/// of one call per character.
public struct CellRun: Equatable, Sendable {
    /// Column of the run's first cell.
    public let startColumn: Int
    public let text: String
    public let foreground: TermColor
    /// The cells' shared background — the renderer needs it to keep a glyph
    /// legible when a program draws it in (nearly) the background color.
    public let background: TermColor
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    /// A double-width glyph (emoji, CJK), which always stands alone: its
    /// placement cannot be left to the run's even cell spacing.
    public let isWide: Bool

    public init(startColumn: Int, text: String, foreground: TermColor,
                background: TermColor, bold: Bool, italic: Bool,
                underline: Bool, isWide: Bool) {
        self.startColumn = startColumn
        self.text = text
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.isWide = isWide
    }
}

public extension CellRun {
    /// Groups a row into runs. Blanks, missing cells and the trailing half of a
    /// wide glyph produce nothing and end the run in progress.
    static func runs(in cells: [TerminalCell?]) -> [CellRun] {
        var runs: [CellRun] = []
        var startColumn = 0
        var text = ""
        var attributes: TerminalCell?

        func flush() {
            guard let attributes, !text.isEmpty else { text = ""; return }
            runs.append(CellRun(startColumn: startColumn, text: text,
                                foreground: attributes.foreground,
                                background: attributes.background,
                                bold: attributes.bold, italic: attributes.italic,
                                underline: attributes.underline,
                                isWide: attributes.width == 2))
            text = ""
        }

        for (column, cell) in cells.enumerated() {
            guard let cell, cell.width > 0, cell.character != " " else {
                flush()
                attributes = nil
                continue
            }
            let matches = attributes.map { sameLook($0, cell) } ?? false
            // A wide glyph never joins a run, and never takes one along.
            if !matches || cell.width == 2 || attributes?.width == 2 {
                flush()
                startColumn = column
                attributes = cell
            }
            text.append(cell.character)
        }
        flush()
        return runs
    }

    private static func sameLook(_ a: TerminalCell, _ b: TerminalCell) -> Bool {
        a.foreground == b.foreground && a.background == b.background
            && a.bold == b.bold && a.italic == b.italic && a.underline == b.underline
    }
}
