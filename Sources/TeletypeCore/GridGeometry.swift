import Foundation

/// Maps between pixel coordinates and grid rows. UI-free so the renderer's
/// clipping rule stays testable.
public enum GridGeometry {
    /// The rows a band of pixels touches, half-open and clamped to the grid.
    /// A row is included as soon as the band reaches into it at all — half a
    /// glyph cannot be drawn.
    ///
    /// `fromY`/`toY` are top-down (the terminal view is flipped), and `padding`
    /// is the inset above the first row.
    public static func rows(fromY: Double, toY: Double,
                            cellHeight: Double, padding: Double,
                            totalRows: Int) -> Range<Int> {
        guard cellHeight > 0, totalRows > 0, toY > fromY else { return 0..<0 }
        let first = Int(floor((fromY - padding) / cellHeight))
        let last = Int(ceil((toY - padding) / cellHeight))     // exclusive
        let start = max(0, first)
        let end = min(totalRows, last)
        return start < end ? start..<end : 0..<0
    }

    /// The pixel band covering a range of rows — what the renderer marks dirty.
    public static func band(forRows rows: Range<Int>,
                            cellHeight: Double, padding: Double) -> (minY: Double, height: Double) {
        guard !rows.isEmpty else { return (0, 0) }
        let minY = padding + Double(rows.lowerBound) * cellHeight
        return (minY, Double(rows.count) * cellHeight)
    }

    /// The rows to repaint: everything that reported a change, plus the rows the
    /// cursor just left and arrived in (its old cell has to be cleared, and a
    /// cursor move alone may not mark anything dirty). Rows outside the grid —
    /// a remembered row after a resize — are dropped.
    public static func rowsToRepaint(dirty: Range<Int>?, cursorRows: [Int],
                                     totalRows: Int) -> Range<Int>? {
        let cursors = cursorRows.filter { $0 >= 0 && $0 < totalRows }
        var lower = dirty?.lowerBound
        var upper = dirty?.upperBound
        for row in cursors {
            lower = min(lower ?? row, row)
            upper = max(upper ?? (row + 1), row + 1)
        }
        guard let start = lower, let end = upper, start < end else { return nil }
        return max(0, start)..<min(totalRows, end)
    }
}
