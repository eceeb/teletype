import Foundation

/// Finds the URL under a grid cell, for ⌘-clicking a link in the output.
public enum LinkDetection {
    /// Schemes worth opening from a terminal. Deliberately short: anything
    /// else would turn ordinary words into links.
    private static let schemes = ["https://", "http://", "file://", "ftp://"]

    /// Trailing characters that end a sentence rather than the URL. Compilers
    /// and shells write "see https://x.dev/y." all the time.
    private static let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "'", "\"", ">"]

    /// The URL covering `column`, with the half-open range of cells it occupies.
    /// Columns are grid cells, so the line is walked by Character.
    public static func url(in line: String, atColumn column: Int) -> (text: String, range: Range<Int>)? {
        let characters = Array(line)
        guard column >= 0, column < characters.count else { return nil }

        // A URL runs to the next whitespace, so find the token around the column.
        var start = column
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        var end = column
        while end < characters.count, !characters[end].isWhitespace { end += 1 }

        // Opening brackets belong to the surrounding text, not the link.
        while start < end, "([{<'\"".contains(characters[start]) { start += 1 }
        while end > start, let last = characters[safe: end - 1], trailing.contains(last) { end -= 1 }
        guard start <= column, column < end else { return nil }

        let token = String(characters[start..<end])
        guard schemes.contains(where: { token.lowercased().hasPrefix($0) }),
              token.count > (schemes.first { token.lowercased().hasPrefix($0) }?.count ?? 0)
        else { return nil }
        return (token, start..<end)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
