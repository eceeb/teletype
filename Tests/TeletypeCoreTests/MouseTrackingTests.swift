import Testing
import Foundation
@testable import TeletypeCore

/// The emulator side: picking up the DECSET modes a program enables, and
/// putting a mouse event back on the wire.
struct MouseTrackingTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 80, rows: 24)
    }

    @Test func trackingIsOffUntilAProgramAsksForIt() {
        #expect(emulator().mouseTracking == .off)
    }

    @Test func eachDecsetModeMapsToItsTracking() {
        let cases: [(String, MouseTracking)] = [
            ("\u{1b}[?9h", .pressOnly),           // X10
            ("\u{1b}[?1000h", .pressAndRelease),  // VT200
            ("\u{1b}[?1002h", .withDrag),         // button-event tracking
            ("\u{1b}[?1003h", .anyMotion)         // any-event tracking
        ]
        for (sequence, expected) in cases {
            let terminal = emulator()
            terminal.feed(Data(sequence.utf8))
            #expect(terminal.mouseTracking == expected, "for \(sequence.debugDescription)")
        }
    }

    @Test func leavingTheModeTurnsTrackingOff() {
        let terminal = emulator()
        terminal.feed(Data("\u{1b}[?1002h".utf8))
        terminal.feed(Data("\u{1b}[?1002l".utf8))
        #expect(terminal.mouseTracking == .off)
    }

    @Test func aClickGoesOutInSGRForm() {
        let terminal = emulator()
        var sent = Data()
        terminal.onRespond = { sent.append($0) }
        terminal.feed(Data("\u{1b}[?1000h\u{1b}[?1006h".utf8))   // VT200 + SGR

        terminal.sendMouse(.press, button: .left, modifiers: [], column: 5, row: 2)

        // CSI < Cb ; col ; row M — coordinates are 1-based on the wire.
        #expect(String(decoding: sent, as: UTF8.self) == "\u{1b}[<0;6;3M")
    }

    @Test func aReleaseUsesTheLowercaseTerminator() {
        let terminal = emulator()
        var sent = Data()
        terminal.feed(Data("\u{1b}[?1000h\u{1b}[?1006h".utf8))
        terminal.onRespond = { sent.append($0) }

        terminal.sendMouse(.release, button: .left, modifiers: [], column: 5, row: 2)

        #expect(String(decoding: sent, as: UTF8.self) == "\u{1b}[<0;6;3m")
    }

    @Test func anUnwantedEventIsNotSent() {
        let terminal = emulator()
        var sent = Data()
        terminal.feed(Data("\u{1b}[?1000h\u{1b}[?1006h".utf8))   // no drag tracking
        terminal.onRespond = { sent.append($0) }

        terminal.sendMouse(.drag, button: .left, modifiers: [], column: 5, row: 2)

        #expect(sent.isEmpty)
    }

    @Test func nothingIsSentWhileTrackingIsOff() {
        let terminal = emulator()
        var sent = Data()
        terminal.onRespond = { sent.append($0) }

        terminal.sendMouse(.press, button: .left, modifiers: [], column: 1, row: 1)

        #expect(sent.isEmpty)
    }
}
