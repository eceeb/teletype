import Testing
import Foundation
@testable import TeletypeCore

struct TerminalEmulatorTests {
    @Test func parsesPlainTextIntoTheGrid() {
        let term = TerminalEmulator(columns: 80, rows: 24)
        term.feed(Data("hello".utf8))
        #expect(term.line(0) == "hello")
    }
}
