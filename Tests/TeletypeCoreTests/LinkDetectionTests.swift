import Testing
@testable import TeletypeCore

/// Finding the URL under the pointer, so ⌘-click can open it.
struct LinkDetectionTests {
    private func url(_ line: String, at column: Int) -> String? {
        LinkDetection.url(in: line, atColumn: column)?.text
    }

    @Test func findsAnHttpsURLUnderThePointer() {
        let line = "see https://example.com/docs for details"
        #expect(url(line, at: 10) == "https://example.com/docs")
        #expect(url(line, at: 4) == "https://example.com/docs")   // first character
        #expect(url(line, at: 27) == "https://example.com/docs")  // last character
    }

    @Test func thereIsNoURLOutsideIt() {
        let line = "see https://example.com/docs for details"
        #expect(url(line, at: 0) == nil)
        #expect(url(line, at: 30) == nil)
    }

    @Test func plainHttpAndOtherSchemesCount() {
        #expect(url("http://localhost:3000/x", at: 2) == "http://localhost:3000/x")
        #expect(url("file:///tmp/report.html", at: 2) == "file:///tmp/report.html")
    }

    @Test func textThatIsNotAURLIsNotOne() {
        #expect(url("just some words here", at: 5) == nil)
        #expect(url("path/to/file.txt", at: 5) == nil)
    }

    @Test func trailingPunctuationIsNotPartOfTheLink() {
        // Compilers and shells love to write "see https://x.dev/y." — the full
        // stop ends the sentence, not the URL.
        #expect(url("see https://x.dev/y.", at: 10) == "https://x.dev/y")
        #expect(url("see https://x.dev/y, and", at: 10) == "https://x.dev/y")
        #expect(url("(https://x.dev/y)", at: 5) == "https://x.dev/y")
    }

    @Test func aPathInsideTheURLSurvives() {
        #expect(url("https://x.dev/a.b.c/d", at: 3) == "https://x.dev/a.b.c/d")
    }

    @Test func theRangeMarksTheCellsToUnderline() {
        let hit = LinkDetection.url(in: "see https://x.dev here", atColumn: 8)
        #expect(hit?.range == 4..<17)   // "see " + 13 characters
    }

    @Test func columnsAreGridCellsNotStringIndices() {
        // A wide glyph before the URL must not shift the reported columns.
        let hit = LinkDetection.url(in: "漢 https://x.dev", atColumn: 5)
        #expect(hit?.text == "https://x.dev")
        #expect(hit?.range.lowerBound == 2)
    }
}
