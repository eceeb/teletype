import Foundation

/// The terminal font size and how ⌘+ / ⌘− / ⌘0 move it. Shares its bounds with
/// the Settings slider so both agree.
public enum FontScaling {
    public static let minimum: Double = 8
    public static let maximum: Double = 28
    public static let defaultSize: Double = 13

    /// One step up or down, clamped, and snapped to whole points — the slider
    /// steps by 1, so the keyboard must not leave a half point behind.
    public static func stepped(_ size: Double, by delta: Double) -> Double {
        // From a fractional size, step to the next whole point in that
        // direction: 13.5 goes up to 14 and down to 13, not 15 and 12.
        let stepped = delta > 0 ? floor(size) + delta : ceil(size) + delta
        return min(maximum, max(minimum, stepped.rounded()))
    }
}
