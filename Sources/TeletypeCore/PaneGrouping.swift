import Foundation

/// Decides how a tab's panes are labelled in the sidebar.
///
/// If the panes share a common root folder, that root's name becomes a group
/// header and each pane is shown by its path *below* that root. The shared root
/// is the deepest common ancestor, backed off by one level so every pane keeps
/// at least one trailing component (e.g. `…/teletype` + `…/teletype/Tests`
/// → header "e", rows "teletype" and "teletype/Tests"). With no shared root
/// each pane shows its own "parent/current" label.
public enum PaneGrouping {
    public struct Result: Equatable, Sendable {
        public let header: String?
        public let labels: [String]
    }

    public static func summarize(_ cwds: [String]) -> Result {
        let lists = cwds.map { $0.split(separator: "/").map(String.init) }
        let rootDepth = cwds.count >= 2 ? commonRootDepth(lists) : 0
        if rootDepth > 0 {
            let header = lists[0][rootDepth - 1]
            let labels = lists.map { $0[rootDepth...].joined(separator: "/") }
            return Result(header: header, labels: labels)
        }
        return Result(header: nil, labels: lists.map(parentAndCurrent))
    }

    /// Leading path components shared by every pane, capped so each pane keeps
    /// at least one trailing component to display.
    private static func commonRootDepth(_ lists: [[String]]) -> Int {
        guard let first = lists.first else { return 0 }
        let minCount = lists.map(\.count).min() ?? 0
        guard minCount > 0 else { return 0 }
        var shared = 0
        while shared < minCount, lists.allSatisfy({ $0[shared] == first[shared] }) {
            shared += 1
        }
        return min(shared, minCount - 1)
    }

    /// The last two path components, e.g. "mailing-editor/frontend".
    private static func parentAndCurrent(_ components: [String]) -> String {
        guard !components.isEmpty else { return "Shell" }
        return components.count >= 2 ? components.suffix(2).joined(separator: "/") : components[0]
    }
}
