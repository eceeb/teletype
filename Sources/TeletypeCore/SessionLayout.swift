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

/// The whole window: one `PaneNode` tree per tab, in order.
public struct SessionLayout: Codable, Equatable, Sendable {
    public var tabs: [PaneNode]

    public init(tabs: [PaneNode]) {
        self.tabs = tabs
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) -> SessionLayout? {
        try? JSONDecoder().decode(SessionLayout.self, from: data)
    }
}
