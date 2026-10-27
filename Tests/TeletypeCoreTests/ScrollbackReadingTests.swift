import Testing
import Foundation
@testable import TeletypeCore

/// Reading the whole buffer — what search runs over — and scrolling to a hit.
struct ScrollbackReadingTests {
    private func emulator(rows: Int = 5) -> TerminalEmulator {
        TerminalEmulator(columns: 40, rows: rows, scrollback: 200)
    }

    @Test func everyLineWrittenIsReadableByItsAbsoluteRow() {
        let terminal = emulator()
        for line in 0..<20 { terminal.feed(Data("line \(line)\r\n".utf8)) }

        let lines = terminal.bufferLines()

        // Rows 0…19 hold what was written, in order, scrollback included.
        for line in 0..<20 {
            #expect(lines[line] == "line \(line)", "row \(line) was \(lines[line].debugDescription)")
        }
    }

    @Test func theBufferCoversTheScrollbackPlusTheVisibleRows() {
        let terminal = emulator(rows: 5)
        for line in 0..<20 { terminal.feed(Data("line \(line)\r\n".utf8)) }
        // 20 written lines, then the cursor's own row and the rest of the screen.
        #expect(terminal.bufferLines().count == terminal.scrollOffset + terminal.rows)
    }

    @Test func readingTheBufferLeavesTheViewportWhereItWas() {
        let terminal = emulator()
        for line in 0..<20 { terminal.feed(Data("line \(line)\r\n".utf8)) }
        terminal.scroll(lines: 4)
        let before = terminal.scrollOffset

        _ = terminal.bufferLines()

        #expect(terminal.scrollOffset == before)
    }

    @Test func aFreshTerminalReadsAsBlankLines() {
        let terminal = emulator(rows: 5)
        let blank = terminal.bufferLines().filter { !$0.isEmpty }
        #expect(blank.isEmpty)
    }

    @Test func scrollingToARowPutsItOnScreen() {
        let terminal = emulator(rows: 5)
        for line in 0..<40 { terminal.feed(Data("line \(line)\r\n".utf8)) }

        terminal.scrollToReveal(absoluteRow: 10)

        // The row must be visible, i.e. within [scrollOffset, +rows).
        let offset = terminal.scrollOffset
        #expect(10 >= offset && 10 < offset + terminal.rows)
        #expect(terminal.isScrolledBack)
    }

    @Test func revealingARowNearTheBottomStaysInsideTheBuffer() {
        let terminal = emulator(rows: 5)
        for line in 0..<40 { terminal.feed(Data("line \(line)\r\n".utf8)) }

        terminal.scrollToReveal(absoluteRow: terminal.bufferLines().count - 1)

        #expect(terminal.scrollOffset >= 0)
        #expect(terminal.scrollOffset <= 40)
    }
}
