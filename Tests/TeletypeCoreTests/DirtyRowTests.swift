import Testing
import Foundation
@testable import TeletypeCore

/// Which rows changed since the last redraw, so the renderer can repaint a line
/// or two instead of the whole grid.
struct DirtyRowTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 20, rows: 6, scrollback: 50)
    }

    @Test func writingOneLineDirtiesOnlyThatRow() {
        let terminal = emulator()
        _ = terminal.takeDirtyRows()                 // drop the startup range
        terminal.feed(Data("hello".utf8))
        #expect(terminal.takeDirtyRows() == 0..<1)
    }

    @Test func writingTwoLinesDirtiesBoth() {
        let terminal = emulator()
        _ = terminal.takeDirtyRows()
        terminal.feed(Data("one\r\ntwo".utf8))
        #expect(terminal.takeDirtyRows() == 0..<2)
    }

    @Test func takingTheRangeClearsIt() {
        let terminal = emulator()
        terminal.feed(Data("hello".utf8))
        _ = terminal.takeDirtyRows()
        // Nothing happened since, so there is nothing to repaint.
        #expect(terminal.takeDirtyRows() == nil)
    }

    @Test func scrollingTheScreenDirtiesEveryRow() {
        let terminal = emulator()
        for line in 0..<6 { terminal.feed(Data("line \(line)\r\n".utf8)) }
        _ = terminal.takeDirtyRows()

        terminal.feed(Data("one more\r\n".utf8))     // pushes everything up

        #expect(terminal.takeDirtyRows() == 0..<6)
    }

    @Test func theRangeNeverLeavesTheGrid() {
        let terminal = emulator()
        for line in 0..<40 { terminal.feed(Data("line \(line)\r\n".utf8)) }
        guard let dirty = terminal.takeDirtyRows() else { return }
        #expect(dirty.lowerBound >= 0)
        #expect(dirty.upperBound <= terminal.rows)
    }
}
