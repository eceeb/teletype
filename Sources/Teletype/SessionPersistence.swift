import Foundation
import TeletypeCore

/// Saves / loads the last window layout (tabs, splits, per-pane directory) in
/// UserDefaults. Tiny JSON — no scrollback, no live processes.
enum SessionPersistence {
    private static let key = "TeletypeSessionLayout"

    static func save(_ layout: SessionLayout) {
        UserDefaults.standard.set(layout.encoded(), forKey: key)
    }

    static func load() -> SessionLayout? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return SessionLayout.decoded(from: data)
    }
}
