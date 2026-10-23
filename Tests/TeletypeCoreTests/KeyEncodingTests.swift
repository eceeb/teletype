import Testing
@testable import TeletypeCore

/// xterm's key encoding. The modifier number is 1 + shift(1) + option(2) +
/// control(4), so ⇧ = 2, ⌥ = 3, ⌃ = 5, ⌃⇧ = 6 …
struct KeyEncodingTests {
    private func encode(_ key: TerminalKey,
                        _ modifiers: KeyModifiers = [],
                        applicationCursor: Bool = false) -> String? {
        TerminalKey.escapeSequence(for: key, modifiers: modifiers,
                                   applicationCursor: applicationCursor)
    }

    @Test func plainArrowsUseTheNormalForm() {
        #expect(encode(.up) == "\u{1b}[A")
        #expect(encode(.down) == "\u{1b}[B")
        #expect(encode(.right) == "\u{1b}[C")
        #expect(encode(.left) == "\u{1b}[D")
    }

    @Test func applicationCursorModeSwitchesToTheOForm() {
        #expect(encode(.up, applicationCursor: true) == "\u{1b}OA")
        #expect(encode(.left, applicationCursor: true) == "\u{1b}OD")
    }

    @Test func modifiersUseTheBracketFormEvenInApplicationMode() {
        // xterm never uses ESC O with a modifier — a shell in application mode
        // would otherwise see ⌥→ as a bare Escape followed by junk.
        #expect(encode(.right, .option, applicationCursor: true) == "\u{1b}[1;3C")
    }

    @Test func eachModifierAddsItsBit() {
        #expect(encode(.right, .shift) == "\u{1b}[1;2C")
        #expect(encode(.right, .option) == "\u{1b}[1;3C")
        #expect(encode(.right, .control) == "\u{1b}[1;5C")
        #expect(encode(.right, [.control, .shift]) == "\u{1b}[1;6C")
        #expect(encode(.right, [.control, .option, .shift]) == "\u{1b}[1;8C")
    }

    @Test func homeAndEndTakeModifiersToo() {
        #expect(encode(.home) == "\u{1b}[H")
        #expect(encode(.end) == "\u{1b}[F")
        #expect(encode(.home, .control) == "\u{1b}[1;5H")
        #expect(encode(.end, .shift) == "\u{1b}[1;2F")
    }

    @Test func tildeKeysPutTheModifierBeforeTheTilde() {
        // ESC[5~ becomes ESC[5;2~ — not ESC[1;2~. Shift-PageUp is what a pager
        // and tmux listen for.
        #expect(encode(.pageUp) == "\u{1b}[5~")
        #expect(encode(.pageDown) == "\u{1b}[6~")
        #expect(encode(.pageUp, .shift) == "\u{1b}[5;2~")
        #expect(encode(.pageDown, .shift) == "\u{1b}[6;2~")
        #expect(encode(.deleteForward) == "\u{1b}[3~")
        #expect(encode(.deleteForward, .control) == "\u{1b}[3;5~")
    }

    @Test func backspaceSendsNothingUnlessOptionIsHeld() {
        // Plain backspace: the key event already carries DEL, so the view sends
        // that. ⌥⌫ is "delete the word before the cursor".
        #expect(encode(.backspace) == nil)
        #expect(encode(.backspace, .option) == "\u{1b}\u{7f}")
        #expect(encode(.backspace, .shift) == nil)
    }
}
