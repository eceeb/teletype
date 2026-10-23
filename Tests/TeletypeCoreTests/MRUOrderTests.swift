import Testing
@testable import TeletypeCore

/// The focus order behind "go back to the pane I was last in" — for closing a
/// pane, switching tabs, and leaving the rename editor.
struct MRUOrderTests {
    @Test func theMostRecentlyRecordedComesFirst() {
        var order = MRUOrder<Int>()
        order.record(1)
        order.record(2)
        order.record(3)
        #expect(order.mostRecent(among: [1, 2, 3]) == 3)
    }

    @Test func recordingAgainMovesToTheFrontWithoutDuplicating() {
        var order = MRUOrder<Int>()
        order.record(1)
        order.record(2)
        order.record(1)
        #expect(order.mostRecent(among: [1, 2]) == 1)
        #expect(order.ids == [1, 2])
    }

    @Test func candidatesNarrowTheChoice() {
        var order = MRUOrder<Int>()
        order.record(1)   // tab A
        order.record(2)   // tab B — most recent overall
        // Switching back to tab A must land on A's own last pane, not on 2.
        #expect(order.mostRecent(among: [1, 3]) == 1)
    }

    @Test func anUnknownCandidateIsStillAnAnswer() {
        var order = MRUOrder<Int>()
        order.record(1)
        // A pane that never had focus (freshly restored tab) is better than none.
        #expect(order.mostRecent(among: [7, 8]) == 7)
    }

    @Test func noCandidatesMeansNoAnswer() {
        var order = MRUOrder<Int>()
        order.record(1)
        #expect(order.mostRecent(among: []) == nil)
    }

    @Test func pruningDropsClosedPanes() {
        var order = MRUOrder<Int>()
        order.record(1)
        order.record(2)
        order.record(3)
        order.prune(keeping: [1, 3])
        #expect(order.ids == [3, 1])
    }
}
