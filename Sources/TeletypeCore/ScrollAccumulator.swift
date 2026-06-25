import Foundation

/// Converts a stream of scroll-wheel / trackpad deltas into whole lines to
/// scroll, carrying the sub-line remainder so slow scrolling isn't lost.
///
/// `scrollingDeltaY` means different things per device:
///   - **Trackpad / Magic Mouse** (`precise == true`): points → divide by the
///     cell height to get lines.
///   - **Classic mouse wheel** (`precise == false`): already line-based, but
///     macOS smooth-scrolling splits a notch into tiny (~0.1) sub-steps, so we
///     accumulate the raw value directly — dividing by the cell height would
///     make slow turns never reach a single line.
public struct ScrollAccumulator {
    private var residue: Double = 0

    public init() {}

    /// Folds one scroll event into the running remainder and returns the number
    /// of whole lines to scroll (positive = toward older output).
    public mutating func lines(delta: Double, precise: Bool, speed: Double, cellHeight: Double) -> Int {
        guard delta != 0 else { return 0 }
        let perLine = precise ? cellHeight : 1
        residue += delta * speed
        let lines = Int(residue / perLine)
        guard lines != 0 else { return 0 }
        residue -= Double(lines) * perLine
        return lines
    }
}
