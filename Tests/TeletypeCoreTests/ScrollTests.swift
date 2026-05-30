import Testing
import Foundation
@testable import TeletypeCore

struct ScrollTests {
    @Test func scrollingBackShowsOlderLines() {
        let term = TerminalEmulator(columns: 80, rows: 5)
        for i in 0..<20 { term.feed(Data("line\(i)\r\n".utf8)) }

        #expect(term.isScrolledBack == false)

        term.scroll(lines: 1000)            // clamps to the top of the scrollback
        #expect(term.isScrolledBack == true)
        #expect(term.line(0) == "line0")    // oldest line is now at the top

        term.scrollToBottom()
        #expect(term.isScrolledBack == false)
    }
}
