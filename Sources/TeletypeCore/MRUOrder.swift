/// Most-recently-used order over opaque ids — the "which pane was I last in?"
/// bookkeeping behind closing a pane, switching tabs, and leaving the rename
/// editor. Kept here (UI-free) so the rule is testable; the app stores
/// `ObjectIdentifier`s of its panes.
public struct MRUOrder<ID: Hashable>: Sendable where ID: Sendable {
    /// Front to back, most recent first. Exposed for tests and debugging.
    public private(set) var ids: [ID] = []

    public init() {}

    /// Moves `id` to the front, without duplicating it.
    public mutating func record(_ id: ID) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
    }

    /// The most recently used of `candidates`. Falls back to the first candidate
    /// when none of them was ever focused — a restored tab has no history, and
    /// landing somewhere beats landing nowhere.
    public func mostRecent(among candidates: [ID]) -> ID? {
        ids.first { candidates.contains($0) } ?? candidates.first
    }

    /// Forgets everything outside `keeping` (panes that have closed).
    public mutating func prune(keeping: [ID]) {
        ids.removeAll { !keeping.contains($0) }
    }
}
