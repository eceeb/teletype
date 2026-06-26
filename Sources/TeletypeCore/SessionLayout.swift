import Foundation

/// A saved window layout: the tab / split-pane structure plus each pane's
/// working directory. Running processes and scrollback are deliberately not
/// stored — only enough to recreate the shape and re-open each shell in place.
public indirect enum PaneNode: Codable, Equatable, Sendable {
    /// A single terminal pane, remembered by its working directory.
    case leaf(cwd: String?)
    /// A split holding two or more children (vertical = side by side).
    case split(vertical: Bool, children: [PaneNode])
}

/// One saved tab: its pane tree plus an optional user-given name. While `name`
/// is nil the sidebar header is derived from the panes' shared folder; once the
/// user renames the group, `name` pins it regardless of the working directory.
public struct SavedTab: Codable, Equatable, Sendable {
    public var name: String?
    public var root: PaneNode

    public init(name: String?, root: PaneNode) {
        self.name = name
        self.root = root
    }

    private enum CodingKeys: String, CodingKey { case name, root }

    /// Backward compatible: older sessions stored each tab as a bare `PaneNode`,
    /// which has no `root` key — fall back to decoding the node directly.
    public init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           keyed.contains(.root) {
            name = try keyed.decodeIfPresent(String.self, forKey: .name)
            root = try keyed.decode(PaneNode.self, forKey: .root)
        } else {
            name = nil
            root = try PaneNode(from: decoder)
        }
    }
}

/// The whole window: one saved tab per window tab, in order.
public struct SessionLayout: Codable, Equatable, Sendable {
    public var tabs: [SavedTab]

    public init(tabs: [SavedTab]) {
        self.tabs = tabs
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) -> SessionLayout? {
        try? JSONDecoder().decode(SessionLayout.self, from: data)
    }
}
