/// Which mouse events a program asked to be told about (DECSET 9/1000/1002/1003).
public enum MouseTracking: Sendable {
    /// Nothing is reported — the mouse belongs to the terminal (selection).
    case off
    /// X10: button presses only.
    case pressOnly
    /// VT200 (1000): presses and releases.
    case pressAndRelease
    /// 1002: plus motion while a button is held.
    case withDrag
    /// 1003: plus motion with no button held.
    case anyMotion
}

public enum MouseButton: Sendable {
    case left, middle, right
}

public enum MouseEventKind: CaseIterable, Sendable {
    case press, release, drag, motion, scrollUp, scrollDown
}

/// Builds xterm's Cb button byte and decides whether an event is wanted at all.
/// SwiftTerm handles the wire format (X10 / SGR / urxvt / utf8) from there.
public enum MouseReport {
    /// Bit layout: 0-1 button, 4 shift, 8 meta, 16 control, 32 motion, 64 wheel.
    public static func buttonFlags(_ kind: MouseEventKind,
                                   button: MouseButton,
                                   modifiers: KeyModifiers) -> Int {
        var flags: Int
        switch kind {
        case .scrollUp:   flags = 64
        case .scrollDown: flags = 65
        // Low bits 3 with no motion bit is how a release is spelled; with the
        // motion bit it means "moved with no button down".
        case .release:    flags = 3
        case .motion:     flags = 3 + 32
        case .drag:       flags = code(of: button) + 32
        case .press:      flags = code(of: button)
        }
        if modifiers.contains(.shift)   { flags += 4 }
        if modifiers.contains(.option)  { flags += 8 }
        if modifiers.contains(.control) { flags += 16 }
        return flags
    }

    public static func shouldReport(_ kind: MouseEventKind, tracking: MouseTracking) -> Bool {
        switch tracking {
        case .off:
            return false
        case .pressOnly:
            // The wheel is the one thing X10 apps still expect: scrolling a
            // pager is the whole reason most of them turn tracking on.
            return kind == .press || kind == .scrollUp || kind == .scrollDown
        case .pressAndRelease:
            return kind != .drag && kind != .motion
        case .withDrag:
            return kind != .motion
        case .anyMotion:
            return true
        }
    }

    private static func code(of button: MouseButton) -> Int {
        switch button {
        case .left:   return 0
        case .middle: return 1
        case .right:  return 2
        }
    }
}
