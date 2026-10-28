import Testing
@testable import TeletypeCore

/// Grouping a row's cells into stretches that share their text attributes, so
/// the renderer can hand each stretch to CoreText in one go instead of drawing
/// character by character.
struct CellRunTests {
    private let white = TermColor(red: 255, green: 255, blue: 255)
    private let red = TermColor(red: 255, green: 0, blue: 0)
    private let black = TermColor(red: 0, green: 0, blue: 0)

    private func cell(_ character: Character, _ foreground: TermColor? = nil,
                      bold: Bool = false, width: Int = 1) -> TerminalCell {
        TerminalCell(character: character, foreground: foreground ?? white,
                     background: black, width: width,
                     bold: bold, italic: false, underline: false)
    }

    private func runs(_ cells: [TerminalCell?]) -> [CellRun] {
        CellRun.runs(in: cells)
    }

    @Test func oneStretchOfSameLookingTextIsOneRun() {
        let hits = runs("hello".map { cell($0) })
        #expect(hits.count == 1)
        #expect(hits[0].text == "hello")
        #expect(hits[0].startColumn == 0)
    }

    @Test func aColorChangeStartsANewRun() {
        let hits = runs([cell("a"), cell("b"), cell("c", red), cell("d", red)])
        #expect(hits.map(\.text) == ["ab", "cd"])
        #expect(hits.map(\.startColumn) == [0, 2])
    }

    @Test func boldStartsANewRunToo() {
        let hits = runs([cell("a"), cell("b", bold: true)])
        #expect(hits.map(\.text) == ["a", "b"])
    }

    @Test func blanksAreNotDrawnAndBreakTheRun() {
        // A space paints no glyph, so there is nothing to hand to CoreText —
        // and the run on either side must keep its own column.
        let hits = runs([cell("a"), cell(" "), cell("b")])
        #expect(hits.map(\.text) == ["a", "b"])
        #expect(hits.map(\.startColumn) == [0, 2])
    }

    @Test func aWideGlyphGetsARunOfItsOwn() {
        // Emoji and CJK span two cells; their placement can't be left to the
        // run's even spacing, so they are kept separate.
        let hits = runs([cell("a"), cell("漢", width: 2), cell("\0", width: 0), cell("b")])
        #expect(hits.map(\.text) == ["a", "漢", "b"])
        #expect(hits.map(\.startColumn) == [0, 1, 3])
        #expect(hits[1].isWide)
        #expect(hits[0].isWide == false)
    }

    @Test func theTrailingHalfOfAWideGlyphIsSkipped() {
        let hits = runs([cell("漢", width: 2), cell("\0", width: 0)])
        #expect(hits.count == 1)
    }

    @Test func missingCellsEndTheRun() {
        let hits = runs([cell("a"), nil, cell("b")])
        #expect(hits.map(\.startColumn) == [0, 2])
    }

    @Test func anEmptyRowHasNoRuns() {
        #expect(runs([]).isEmpty)
        #expect(runs(Array(repeating: cell(" "), count: 10)).isEmpty)
    }

    @Test func aRunCarriesTheAttributesToDrawItWith() {
        let hits = runs([cell("x", red, bold: true)])
        #expect(hits[0].foreground == red)
        #expect(hits[0].background == black)
        #expect(hits[0].bold)
    }

    @Test func aBackgroundChangeStartsANewRun() {
        // The legibility nudge is computed against the cell's background, so a
        // run must not span two of them.
        let onRed = TerminalCell(character: "b", foreground: white, background: red,
                                 width: 1, bold: false, italic: false, underline: false)
        #expect(runs([cell("a"), onRed]).map(\.text) == ["a", "b"])
    }
}
