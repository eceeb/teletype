/// The keys that need an escape sequence of their own. Everything else (letters,
/// Return, Tab, plain Backspace) already arrives as the right character.
public enum TerminalKey: Sendable {
    case up, down, right, left
    case home, end
    case pageUp, pageDown
    case deleteForward
    case backspace
}

/// Modifier keys held while pressing one of the above.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift   = KeyModifiers(rawValue: 1 << 0)
    public static let option  = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)

    /// xterm's modifier number: 1 + shift(1) + option(2) + control(4).
    var xtermCode: Int {
        var code = 1
        if contains(.shift)   { code += 1 }
        if contains(.option)  { code += 2 }
        if contains(.control) { code += 4 }
        return code
    }
}

public extension TerminalKey {
    /// The bytes a terminal sends for this key, the way xterm encodes them, or
    /// nil when the key event's own character is already correct.
    ///
    /// Note we deliberately do *not* treat Option as Meta for ordinary letters:
    /// on a German layout Option produces @ | [ ] { } \ ~, so swallowing it
    /// would make those untypeable. Word-wise editing is covered by ⌥←/⌥→/⌥⌫.
    static func escapeSequence(for key: TerminalKey,
                               modifiers: KeyModifiers,
                               applicationCursor: Bool) -> String? {
        let code = modifiers.xtermCode
        let modified = code > 1

        // ESC [ 1 ; <n> <letter>. With a modifier this always wins over the
        // application-cursor form: xterm has no ESC O variant that carries one.
        func cursor(_ letter: String) -> String {
            if modified { return "\u{1b}[1;\(code)\(letter)" }
            return applicationCursor ? "\u{1b}O\(letter)" : "\u{1b}[\(letter)"
        }
        // ESC [ <number> ; <n> ~ — the modifier goes before the tilde, not
        // after a leading 1 the way it does for cursor keys.
        func tilde(_ number: Int) -> String {
            modified ? "\u{1b}[\(number);\(code)~" : "\u{1b}[\(number)~"
        }

        switch key {
        case .up:            return cursor("A")
        case .down:          return cursor("B")
        case .right:         return cursor("C")
        case .left:          return cursor("D")
        case .home:          return modified ? "\u{1b}[1;\(code)H" : "\u{1b}[H"
        case .end:           return modified ? "\u{1b}[1;\(code)F" : "\u{1b}[F"
        case .pageUp:        return tilde(5)
        case .pageDown:      return tilde(6)
        case .deleteForward: return tilde(3)
        // ⌥⌫ deletes the word before the cursor (ESC + DEL); plain ⌫ falls
        // through to the character the key event already carries.
        case .backspace:     return modifiers.contains(.option) ? "\u{1b}\u{7f}" : nil
        }
    }
}
