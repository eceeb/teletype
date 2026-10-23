import Testing
@testable import TeletypeCore

/// Which grid rows a dirty rectangle touches. The renderer redraws only those,
/// instead of pushing every cell of the grid through CoreText on each chunk of
/// output.
struct GridGeometryTests {
    private let cellHeight = 16.0
    private let padding = 4.0
    private let rows = 10          // content spans y = 4 … 164

    private func range(_ minY: Double, _ maxY: Double) -> Range<Int> {
        GridGeometry.rows(fromY: minY, toY: maxY,
                          cellHeight: cellHeight, padding: padding, totalRows: rows)
    }

    @Test func aFullRedrawCoversEveryRow() {
        #expect(range(0, 200) == 0..<10)
    }

    @Test func aSingleRowBandCoversOnlyThatRow() {
        // Row 3 spans y = 52 … 68.
        #expect(range(52, 68) == 3..<4)
    }

    @Test func aBandStraddlingTwoRowsCoversBoth() {
        #expect(range(60, 72) == 3..<5)
    }

    @Test func partialCoverageStillRedrawsTheWholeRow() {
        // One pixel into row 3 is enough — half a glyph can't be drawn.
        #expect(range(67.9, 68.1) == 3..<5)
    }

    @Test func theRangeIsClampedToTheGrid() {
        #expect(range(-500, 5000) == 0..<10)
        #expect(range(1000, 2000).isEmpty)
    }

    @Test func anEmptyRectDrawsNothing() {
        #expect(range(50, 50).isEmpty)
        #expect(range(80, 20).isEmpty)
    }

    @Test func thePaddingAboveTheFirstRowBelongsToNoRow() {
        #expect(range(0, 3).isEmpty)
    }
}

/// Turning changed rows into the band of pixels the renderer must repaint.
struct DirtyBandTests {
    @Test func theBandSpansTheGivenRows() {
        // Rows 2…3 with cellHeight 16, padding 4: y = 36 … 68.
        let band = GridGeometry.band(forRows: 2..<4, cellHeight: 16, padding: 4)
        #expect(band.minY == 36)
        #expect(band.height == 32)
    }

    @Test func anEmptyRangeHasNoBand() {
        #expect(GridGeometry.band(forRows: 3..<3, cellHeight: 16, padding: 4).height == 0)
    }

    @Test func theCursorRowsJoinTheDirtyRange() {
        // The cursor left row 1 and arrived in row 5; both have to be repainted
        // even though only row 5 reported a change.
        #expect(GridGeometry.rowsToRepaint(dirty: 5..<6, cursorRows: [1, 5], totalRows: 10) == 1..<6)
    }

    @Test func aMovedCursorAloneIsEnoughToRepaint() {
        #expect(GridGeometry.rowsToRepaint(dirty: nil, cursorRows: [2, 3], totalRows: 10) == 2..<4)
    }

    @Test func nothingChangedMeansNoRepaint() {
        #expect(GridGeometry.rowsToRepaint(dirty: nil, cursorRows: [], totalRows: 10) == nil)
    }

    @Test func cursorRowsOutsideTheGridAreIgnored() {
        // After a resize the remembered row can be past the bottom.
        #expect(GridGeometry.rowsToRepaint(dirty: 1..<2, cursorRows: [99, -3], totalRows: 10) == 1..<2)
    }
}
