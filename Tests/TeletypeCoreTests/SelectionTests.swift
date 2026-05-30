import Testing
import Foundation
@testable import TeletypeCore

struct SelectionTextTests {
    private func emulator(_ bytes: String) -> TerminalEmulator {
        let term = TerminalEmulator(columns: 80, rows: 24)
        term.feed(Data(bytes.utf8))
        return term
    }

    @Test func singleRowRange() {
        let term = emulator("hello world")
        let text = term.text(from: GridPosition(row: 0, column: 0),
                             to: GridPosition(row: 0, column: 4))
        #expect(text == "hello")
    }

    @Test func multiRowRange() {
        let term = emulator("abc\r\ndef")
        // First row from the start column to its end, last row up to the end column.
        let text = term.text(from: GridPosition(row: 0, column: 1),
                             to: GridPosition(row: 1, column: 1))
        #expect(text == "bc\nde")
    }

    @Test func normalizesReversedRange() {
        let term = emulator("hello")
        let text = term.text(from: GridPosition(row: 0, column: 4),
                             to: GridPosition(row: 0, column: 0))
        #expect(text == "hello")
    }

    @Test func trimsTrailingWhitespace() {
        let term = emulator("hi")
        // Selecting the whole padded row yields just the text.
        let text = term.text(from: GridPosition(row: 0, column: 0),
                             to: GridPosition(row: 0, column: 79))
        #expect(text == "hi")
    }

    @Test func wordRangeSelectsContiguousNonSpace() {
        let term = emulator("foo bar baz")          // "bar" is columns 4...6
        let (start, end) = term.wordRange(at: GridPosition(row: 0, column: 5))
        #expect(start == GridPosition(row: 0, column: 4))
        #expect(end == GridPosition(row: 0, column: 6))
    }

    @Test func lineRangeCoversRowContent() {
        let term = emulator("hello")
        let (start, end) = term.lineRange(atRow: 0)
        #expect(start == GridPosition(row: 0, column: 0))
        #expect(end == GridPosition(row: 0, column: 4))
    }
}
