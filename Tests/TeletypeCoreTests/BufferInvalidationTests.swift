import Testing
import Foundation
@testable import TeletypeCore

/// Selections are anchored to buffer-absolute rows, so they survive scrolling
/// and new output. They only become meaningless when those row numbers start
/// pointing at different text — switching screens, or dropping the scrollback.
struct BufferInvalidationTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 20, rows: 5, scrollback: 100)
    }

    @Test func ordinaryOutputDoesNotInvalidate() {
        let terminal = emulator()
        var invalidations = 0
        terminal.onBufferInvalidated = { invalidations += 1 }

        terminal.feed(Data("hello\r\n".utf8))
        terminal.feed(Data("world\r\n".utf8))

        // This is the whole point: a running build must not drop the selection.
        #expect(invalidations == 0)
    }

    @Test func outputThatScrollsTheBufferDoesNotInvalidate() {
        let terminal = emulator()
        var invalidations = 0
        terminal.onBufferInvalidated = { invalidations += 1 }

        for line in 0..<20 { terminal.feed(Data("line \(line)\r\n".utf8)) }

        // Rows move into the scrollback, but an absolute row still names the
        // same text, so the selection stays valid.
        #expect(invalidations == 0)
    }

    @Test func enteringAndLeavingTheAlternateScreenInvalidates() {
        let terminal = emulator()
        var invalidations = 0
        terminal.onBufferInvalidated = { invalidations += 1 }

        terminal.feed(Data("\u{1b}[?1049h".utf8))     // less / vim opens
        #expect(invalidations == 1)
        terminal.feed(Data("pager content".utf8))
        #expect(invalidations == 1)                    // drawing in it is ordinary
        terminal.feed(Data("\u{1b}[?1049l".utf8))     // and quits
        #expect(invalidations == 2)
    }

    @Test func clearingTheScrollbackInvalidates() {
        let terminal = emulator()
        for line in 0..<20 { terminal.feed(Data("line \(line)\r\n".utf8)) }
        var invalidations = 0
        terminal.onBufferInvalidated = { invalidations += 1 }

        terminal.feed(Data("\u{1b}[3J".utf8))          // ED 3 — drop the scrollback

        // Absolute rows now point at different lines than the user selected.
        #expect(invalidations == 1)
    }
}
