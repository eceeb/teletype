import Testing
import Foundation
@testable import TeletypeCore

/// Operating System Commands a program can send: set the terminal's colors,
/// put something on the clipboard, raise a notification.
struct OSCTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 20, rows: 5)
    }

    // MARK: - OSC 10/11/12: colors

    @Test func aProgramCanSetTheForegroundAndBackground() {
        let terminal = emulator()
        var changes = 0
        terminal.onColorsChanged = { changes += 1 }

        terminal.feed(Data("\u{1b}]11;rgb:1a/1b/26\u{7}".utf8))   // background
        terminal.feed(Data("\u{1b}]10;rgb:c0/ca/f5\u{7}".utf8))   // foreground

        #expect(terminal.programBackground == TermColor(red: 0x1a, green: 0x1b, blue: 0x26))
        #expect(terminal.programForeground == TermColor(red: 0xc0, green: 0xca, blue: 0xf5))
        #expect(changes == 2)
    }

    @Test func withoutOSCTheProgramColorsAreUnset() {
        let terminal = emulator()
        #expect(terminal.programForeground == nil)
        #expect(terminal.programBackground == nil)
    }

    @Test func theHandlerMayReadTheColorsBack() {
        // What the app actually does: repaint from the new colors. Reading them
        // inside the callback used to trap on exclusive access.
        let terminal = emulator()
        var seen: TermColor?
        terminal.onColorsChanged = { seen = terminal.programBackground }

        terminal.feed(Data("\u{1b}]11;rgb:10/14/30\u{7}".utf8))

        #expect(seen == TermColor(red: 0x10, green: 0x14, blue: 0x30))
    }

    @Test func aCursorColorComesThroughToo() {
        let terminal = emulator()
        terminal.feed(Data("\u{1b}]12;rgb:ff/00/88\u{7}".utf8))
        #expect(terminal.programCursorColor == TermColor(red: 0xff, green: 0x00, blue: 0x88))
    }

    // MARK: - OSC 52: clipboard

    @Test func aProgramCanPutTextOnTheClipboard() {
        let terminal = emulator()
        var copied: String?
        terminal.onClipboardCopy = { copied = $0 }

        // OSC 52 ; c ; <base64> BEL — what tmux and vim send over SSH.
        let payload = Data("hello from ssh".utf8).base64EncodedString()
        terminal.feed(Data("\u{1b}]52;c;\(payload)\u{7}".utf8))

        #expect(copied == "hello from ssh")
    }

    @Test func readingTheClipboardIsRefused() {
        // A program asking to *read* the clipboard would be handing itself
        // whatever the user last copied — a password, say. We never answer.
        let terminal = emulator()
        var sent = Data()
        terminal.onRespond = { sent.append($0) }
        terminal.feed(Data("\u{1b}]52;c;?\u{7}".utf8))
        #expect(sent.isEmpty)
    }

    // MARK: - OSC 777: notification

    @Test func aProgramCanRaiseANotification() {
        // The urxvt form, ESC ] 777 ; notify ; title ; body BEL — iTerm's
        // shorter OSC 9 is not part of the parser we build on.
        let terminal = emulator()
        var received: (title: String, body: String)?
        terminal.onNotify = { received = (title: $0, body: $1) }

        terminal.feed(Data("\u{1b}]777;notify;Build;finished in 3s\u{7}".utf8))

        #expect(received?.title == "Build")
        #expect(received?.body == "finished in 3s")
    }

    @Test func aMalformedNotificationIsIgnored() {
        let terminal = emulator()
        var received = false
        terminal.onNotify = { _, _ in received = true }
        terminal.feed(Data("\u{1b}]777;something-else;x\u{7}".utf8))
        #expect(received == false)
    }
}
