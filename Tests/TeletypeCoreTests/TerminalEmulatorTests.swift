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
}
