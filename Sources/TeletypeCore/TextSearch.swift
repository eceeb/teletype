import Foundation

/// One hit: a buffer-absolute row plus the column and length of the match, so
/// the view can scroll to it and highlight it like a selection.
public struct SearchMatch: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let length: Int

    public init(row: Int, column: Int, length: Int) {
        self.row = row
        self.column = column
        self.length = length
    }
}

/// Plain substring search over the scrollback.
public enum TextSearch {
    public static func matches(of needle: String, in lines: [String],
                               caseSensitive: Bool) -> [SearchMatch] {
        guard !needle.isEmpty else { return [] }
        let pattern = Array(caseSensitive ? needle : needle.lowercased())

        var hits: [SearchMatch] = []
        for (row, line) in lines.enumerated() {
            // Compare by Character, not by String index: a column is a grid
            // cell, and a wide glyph or combining mark must not shift it.
            let characters = Array(caseSensitive ? line : line.lowercased())
            guard characters.count >= pattern.count else { continue }
            var column = 0
            while column <= characters.count - pattern.count {
                if Array(characters[column..<(column + pattern.count)]) == pattern {
                    hits.append(SearchMatch(row: row, column: column, length: pattern.count))
                    column += pattern.count     // a hit consumes its own text
                } else {
                    column += 1
                }
            }
        }
        return hits
    }

    /// The hit after `current` in document order, wrapping at the end. Passing
    /// nil starts at the first hit.
    public static func next(after current: SearchMatch?, in hits: [SearchMatch]) -> SearchMatch? {
        guard !hits.isEmpty else { return nil }
        guard let current else { return hits.first }
        return hits.first { ($0.row, $0.column) > (current.row, current.column) } ?? hits.first
    }

    /// The hit before `current`, wrapping at the start.
    public static func previous(before current: SearchMatch?, in hits: [SearchMatch]) -> SearchMatch? {
        guard !hits.isEmpty else { return nil }
        guard let current else { return hits.last }
        return hits.last { ($0.row, $0.column) < (current.row, current.column) } ?? hits.last
    }
}
