import Testing
import Foundation
@testable import TeletypeCore

/// What ⌘A selects: everything written, not the blank rows below it.
struct ContentRangeTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 20, rows: 6, scrollback: 100)
    }

    @Test func itSpansFromTheFirstRowToTheLastNonEmptyOne() {
        let terminal = emulator()
        terminal.feed(Data("first\r\nsecond\r\n".utf8))

        let range = terminal.contentRange()

        #expect(range?.start == GridPosition(row: 0, column: 0))
        #expect(range?.end.row == 1)                 // "second", not the blanks below
        #expect(range?.end.column == 5)              // its last character
    }

    @Test func itReachesIntoTheScrollback() {
        let terminal = emulator()
        for line in 0..<30 { terminal.feed(Data("line \(line)\r\n".utf8)) }

        let range = terminal.contentRange()

        #expect(range?.start.row == 0)               // the oldest line, off screen
        #expect(range?.end.row == 29)
    }

    @Test func anEmptyTerminalHasNothingToSelect() {
        #expect(emulator().contentRange() == nil)
    }
}
