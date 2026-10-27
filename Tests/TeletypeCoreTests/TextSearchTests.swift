import Testing
@testable import TeletypeCore

/// Finding text in the scrollback. Rows are buffer-absolute, so a hit can be
/// scrolled to and highlighted exactly like a selection.
struct TextSearchTests {
    private let lines = [
        "error: build failed",
        "warning: unused variable",
        "ERROR: second one",
        "",
        "the error is here and error again"
    ]

    private func find(_ needle: String, caseSensitive: Bool = false) -> [SearchMatch] {
        TextSearch.matches(of: needle, in: lines, caseSensitive: caseSensitive)
    }

    @Test func findsEveryOccurrenceWithItsPosition() {
        let hits = find("warning")
        #expect(hits == [SearchMatch(row: 1, column: 0, length: 7)])
    }

    @Test func ignoresCaseByDefault() {
        let rows = find("error").map(\.row)
        #expect(rows == [0, 2, 4, 4])
    }

    @Test func caseSensitiveSearchNarrowsIt() {
        let rows = find("ERROR", caseSensitive: true).map(\.row)
        #expect(rows == [2])
    }

    @Test func severalHitsInOneRowAreAllReported() {
        let hits = find("error").filter { $0.row == 4 }
        #expect(hits.map(\.column) == [4, 22])
    }

    @Test func overlappingMatchesAdvancePastTheLastHit() {
        // "aaaa" contains "aa" twice, not three times — a hit consumes its text.
        let hits = TextSearch.matches(of: "aa", in: ["aaaa"], caseSensitive: true)
        #expect(hits.map(\.column) == [0, 2])
    }

    @Test func anEmptyNeedleFindsNothing() {
        #expect(find("").isEmpty)
    }

    @Test func nothingMatchesNothing() {
        #expect(find("zzz").isEmpty)
    }

    @Test func columnsCountCharactersNotBytes() {
        // A row with wide glyphs must still report the column the cell sits in.
        let hits = TextSearch.matches(of: "ziel", in: ["漢字 ziel"], caseSensitive: true)
        #expect(hits == [SearchMatch(row: 0, column: 3, length: 4)])
    }

    @Test func theNextHitAfterAPositionWrapsAround() {
        let hits = find("error")
        // Searching forward from row 2 lands on row 4; from the last hit it
        // wraps back to the first, the way ⌘G does everywhere.
        #expect(TextSearch.next(after: SearchMatch(row: 2, column: 0, length: 5), in: hits)?.row == 4)
        #expect(TextSearch.next(after: hits.last!, in: hits)?.row == 0)
        #expect(TextSearch.next(after: nil, in: hits)?.row == 0)
        #expect(TextSearch.next(after: nil, in: []) == nil)
    }

    @Test func thePreviousHitWrapsTheOtherWay() {
        let hits = find("error")
        #expect(TextSearch.previous(before: hits[0], in: hits)?.row == 4)
        #expect(TextSearch.previous(before: hits[2], in: hits)?.row == 2)
    }
}
