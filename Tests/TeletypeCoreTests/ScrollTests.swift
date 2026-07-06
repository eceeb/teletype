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

    /// `clear` on a full scrollback emits ED 3 (\u{1b}[3J), which drops yBase and
    /// yDisp without a scroll event. The tracked live bottom must follow, or the
    /// view is left wrongly "scrolled back" and jumps far past the end on the next
    /// scroll-to-bottom — the screen renders garbage.
    @Test func clearOnFullScrollbackStaysAtBottom() {
        let term = TerminalEmulator(columns: 20, rows: 5)
        func feed(_ s: String) { term.feed(Data(s.utf8)) }

        for i in 1...400 { feed("\(i)\r\n") }       // seq 400 → large scrollback
        feed("\u{1b}[3J\u{1b}[H\u{1b}[2J")          // exactly what `clear` sends
        term.scrollToBottom()                       // the view does this on output
        feed("PROMPT>")                             // the shell redraws its prompt

        #expect(term.isScrolledBack == false)
        let cursor = term.cursorPosition
        #expect(term.line(cursor.row).hasPrefix("PROMPT>"))
    }

    /// A resize (window resize, or switching to a pane with a different row count)
    /// reflows the buffer and moves yBase without a scroll event. The live bottom
    /// must follow, or afterwards the view is wrongly "scrolled back" and typing
    /// jumps the viewport away from the cursor.
    @Test func cursorStaysAlignedAfterResize() {
        let term = TerminalEmulator(columns: 40, rows: 5)
        func feed(_ s: String) { term.feed(Data(s.utf8)) }

        for i in 1...60 { feed("line \(i)\r\n") }    // scrollback, sitting at the bottom
        feed("PROMPT>")
        term.resize(columns: 40, rows: 12)           // e.g. switch to a taller pane
        term.scrollToBottom()                        // the view does this on typing

        #expect(term.isScrolledBack == false)
        let cursor = term.cursorPosition
        #expect(term.line(cursor.row).hasPrefix("PROMPT>"))
    }

    /// Even if the live bottom drifts (a resize while scrolled back moves yBase
    /// with no scroll event), following output must re-anchor it — the view can't
    /// stay permanently wedged as "scrolled back".
    @Test func liveBottomRecoversAfterDriftingViaOutput() {
        let term = TerminalEmulator(columns: 40, rows: 5)
        func feed(_ s: String) { term.feed(Data(s.utf8)) }
        for i in 1...60 { feed("line \(i)\r\n") }
        term.scroll(lines: 40)                 // user scrolls back
        term.resize(columns: 40, rows: 15)     // resize while scrolled back → drift
        for i in 1...20 { feed("out \(i)\r\n") }   // more output re-anchors it
        feed("PROMPT>")
        #expect(!term.isScrolledBack)
        #expect(term.line(term.cursorPosition.row).hasPrefix("PROMPT>"))
    }

    /// The configured scrollback size is honored: a tiny history drops old lines,
    /// a large one keeps them (SwiftTerm's own default of 500 is easy to exceed).
    @Test func scrollbackSizeIsHonored() {
        func oldestLine(scrollback: Int) -> String {
            let term = TerminalEmulator(columns: 20, rows: 5, scrollback: scrollback)
            for i in 0..<300 { term.feed(Data("line\(i)\r\n".utf8)) }
            term.scroll(lines: 1_000_000)          // jump to the very top
            return term.line(0)
        }
        #expect(oldestLine(scrollback: 10) != "line0")      // line0 fell out of a 10-line history
        #expect(oldestLine(scrollback: 10_000) == "line0")  // 10k keeps all 300
    }
}
