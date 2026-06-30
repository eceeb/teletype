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

    /// A full-screen pager (git uses `less`, which switches to the alternate
    /// screen) must not leave the cursor mis-aligned after it exits. Regression:
    /// alt-screen scroll events corrupted the tracked live bottom, so afterwards
    /// the view was shifted out from under the cursor — typing showed up on a
    /// different row than the drawn cursor.
    @Test func cursorStaysAlignedAfterAlternateBufferPager() {
        let term = TerminalEmulator(columns: 20, rows: 5)
        func feed(_ s: String) { term.feed(Data(s.utf8)) }

        for i in 0..<12 { feed("line\(i)\r\n") }    // build a scrollback (yBase > 0)
        feed("PROMPT>")                             // cursor sits just after the prompt
        feed("\u{1b}[?1049h")                       // enter the alternate screen
        for i in 0..<12 { feed("pager\(i)\r\n") }   // scroll within it, like a pager
        feed("\u{1b}[?1049l")                       // leave it — back to the prompt
        term.scrollToBottom()                       // the view does this on new output

        #expect(term.isScrolledBack == false)
        let cursor = term.cursorPosition
        #expect(term.line(cursor.row).hasPrefix("PROMPT>"))   // drawn row matches cursor
    }
}
