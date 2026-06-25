import Testing
@testable import TeletypeCore

struct ScrollAccumulatorTests {
    // MARK: - Mouse wheel (non-precise): scrollingDeltaY is already in lines.

    @Test func wheelNoMovementOnZeroDelta() {
        var acc = ScrollAccumulator()
        #expect(acc.lines(delta: 0, precise: false, speed: 3, cellHeight: 18) == 0)
    }

    @Test func wheelAccumulatesSlowTicksIntoALine() {
        // The bug: tiny smooth-scroll sub-steps (~0.1) used to be divided by the
        // cell height, so slow wheel turns never reached a single line.
        var acc = ScrollAccumulator()
        // 0.1 * speed 8 = 0.8 per tick → first tick is still below a line…
        #expect(acc.lines(delta: 0.1, precise: false, speed: 8, cellHeight: 18) == 0)
        // …the second tick crosses 1.0 and scrolls a line.
        #expect(acc.lines(delta: 0.1, precise: false, speed: 8, cellHeight: 18) == 1)
    }

    @Test func wheelDoesNotDivideByCellHeight() {
        // One line-unit of delta at speed 1 must scroll exactly one line,
        // regardless of cell height.
        var acc = ScrollAccumulator()
        #expect(acc.lines(delta: 1, precise: false, speed: 1, cellHeight: 18) == 1)
    }

    @Test func wheelCarriesResidueRatherThanDropping() {
        var acc = ScrollAccumulator()
        // 1.5 lines → 1 now, 0.5 carried over.
        #expect(acc.lines(delta: 1.5, precise: false, speed: 1, cellHeight: 18) == 1)
        // another 1.5 + carried 0.5 = 2.0 → 2 lines.
        #expect(acc.lines(delta: 1.5, precise: false, speed: 1, cellHeight: 18) == 2)
    }

    @Test func wheelScrollsBackwardOnNegativeDelta() {
        var acc = ScrollAccumulator()
        #expect(acc.lines(delta: -2, precise: false, speed: 1, cellHeight: 18) == -2)
    }

    // MARK: - Trackpad (precise): scrollingDeltaY is in points → divide by cell.

    @Test func preciseConvertsPointsToLinesViaCellHeight() {
        var acc = ScrollAccumulator()
        // 18 points at cell height 18, speed 1 → exactly one line.
        #expect(acc.lines(delta: 18, precise: true, speed: 1, cellHeight: 18) == 1)
    }

    @Test func preciseAccumulatesSubCellMovement() {
        var acc = ScrollAccumulator()
        // 10 points < one 18px cell → no line yet…
        #expect(acc.lines(delta: 10, precise: true, speed: 1, cellHeight: 18) == 0)
        // …+10 more = 20 points → one line, 2 points carried.
        #expect(acc.lines(delta: 10, precise: true, speed: 1, cellHeight: 18) == 1)
    }
}
