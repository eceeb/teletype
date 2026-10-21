import Testing
import Foundation
@testable import TeletypeCore

struct TerminalEmulatorTests {
    @Test func parsesPlainTextIntoTheGrid() {
        let term = TerminalEmulator(columns: 80, rows: 24)
        term.feed(Data("hello".utf8))
        #expect(term.line(0) == "hello")
    }

    @Test func reportsItsGridDimensions() {
        let term = TerminalEmulator(columns: 100, rows: 30)
        #expect(term.columns == 100)
        #expect(term.rows == 30)
    }

    @Test func resizeChangesDimensions() {
        let term = TerminalEmulator(columns: 80, rows: 24)
        term.resize(columns: 100, rows: 30)
        #expect(term.columns == 100)
        #expect(term.rows == 30)
    }

    @Test func cursorPositionFollowsText() {
        let term = TerminalEmulator(columns: 80, rows: 24)
        term.feed(Data("abc".utf8))
        #expect(term.cursorPosition == GridPosition(row: 0, column: 3))
    }
}

/// The view needs these two states: the wheel must drive a full-screen program
/// instead of the (non-existent) scrollback, and a paste must be bracketed when
/// the program asked for it, so multi-line pastes don't execute line by line.
@Test func reportsAlternateScreenAndBracketedPaste() {
    let term = TerminalEmulator(columns: 20, rows: 5)
    #expect(term.isAlternateScreen == false)
    #expect(term.bracketedPaste == false)

    term.feed(Data("\u{1b}[?1049h".utf8))      // enter alternate screen (pager/editor)
    #expect(term.isAlternateScreen == true)

    term.feed(Data("\u{1b}[?2004h".utf8))      // DECSET 2004: bracketed paste on
    #expect(term.bracketedPaste == true)

    term.feed(Data("\u{1b}[?1049l".utf8))      // back to the normal screen
    #expect(term.isAlternateScreen == false)
}

