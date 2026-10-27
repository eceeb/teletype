import Testing
import Foundation
@testable import TeletypeCore

/// DECSCUSR: vim switches to a bar in insert mode, back to a block in normal
/// mode. ESC [ <n> SP q, where n is 0/1 blink block, 2 steady block,
/// 3/4 underline, 5/6 bar.
struct CursorStyleTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 20, rows: 5)
    }

    @Test func theDefaultIsABlock() {
        #expect(emulator().cursorStyle.shape == .block)
    }

    @Test func eachCodeSelectsItsShape() {
        let cases: [(Int, CursorShape)] = [
            (1, .block), (2, .block),
            (3, .underline), (4, .underline),
            (5, .bar), (6, .bar)
        ]
        for (code, shape) in cases {
            let terminal = emulator()
            terminal.feed(Data("\u{1b}[\(code) q".utf8))
            #expect(terminal.cursorStyle.shape == shape, "for code \(code)")
        }
    }

    @Test func theOddCodesBlink() {
        let cases: [(Int, Bool)] = [(1, true), (2, false), (3, true), (4, false), (5, true), (6, false)]
        for (code, blinks) in cases {
            let terminal = emulator()
            terminal.feed(Data("\u{1b}[\(code) q".utf8))
            #expect(terminal.cursorStyle.blinks == blinks, "for code \(code)")
        }
    }

    @Test func aProgramCanSwitchBackAndForth() {
        let terminal = emulator()
        terminal.feed(Data("\u{1b}[5 q".utf8))     // entering insert mode
        #expect(terminal.cursorStyle.shape == .bar)
        terminal.feed(Data("\u{1b}[2 q".utf8))     // and leaving it again
        #expect(terminal.cursorStyle.shape == .block)
    }

    @Test func aStyleChangeIsAnnounced() {
        let terminal = emulator()
        var changes = 0
        terminal.onCursorStyleChange = { changes += 1 }
        terminal.feed(Data("\u{1b}[5 q".utf8))
        #expect(changes == 1)
    }
}
