import Foundation
import Testing

/// An in-memory stand-in for `UserDefaults`, used wherever a test needs an
/// isolated settings store.
///
/// `UserDefaults(suiteName:)` writes a real plist into ~/Library/Preferences,
/// and a suite named after a fresh UUID leaves one behind on every run — this
/// test suite had collected 60-odd of them before anyone noticed. Removing the
/// domain is not enough either: cfprefsd owns the file and writes it back after
/// the test has deleted it. So nothing goes to disk in the first place.
final class InMemoryDefaults: UserDefaults {
    private var store: [String: Any] = [:]

    init() { super.init(suiteName: nil)! }

    override func object(forKey key: String) -> Any? { store[key] }
    override func set(_ value: Any?, forKey key: String) { store[key] = value }
    override func removeObject(forKey key: String) { store.removeValue(forKey: key) }
    override func string(forKey key: String) -> String? { store[key] as? String }
    override func array(forKey key: String) -> [Any]? { store[key] as? [Any] }
    override func data(forKey key: String) -> Data? { store[key] as? Data }
    override func integer(forKey key: String) -> Int { store[key] as? Int ?? 0 }
    override func double(forKey key: String) -> Double { store[key] as? Double ?? 0 }
    override func bool(forKey key: String) -> Bool { store[key] as? Bool ?? false }
}

/// Runs `body` against a settings store that exists only for its duration.
func withTemporaryDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    try body(InMemoryDefaults())
}

struct TemporaryDefaultsTests {
    @Test func itStoresAndReadsBack() {
        withTemporaryDefaults { defaults in
            defaults.set(42, forKey: "answer")
            defaults.set("hi", forKey: "greeting")
            #expect(defaults.object(forKey: "answer") as? Int == 42)
            #expect(defaults.string(forKey: "greeting") == "hi")
        }
    }

    @Test func removingAKeyClearsIt() {
        withTemporaryDefaults { defaults in
            defaults.set("x", forKey: "k")
            defaults.removeObject(forKey: "k")
            #expect(defaults.object(forKey: "k") == nil)
        }
    }

    @Test func eachStoreIsIsolated() {
        withTemporaryDefaults { first in
            first.set("one", forKey: "shared")
            withTemporaryDefaults { second in
                #expect(second.string(forKey: "shared") == nil)
            }
        }
    }

    @Test func nothingReachesTheDisk() {
        // The regression itself: a test run must not leave plists behind.
        withTemporaryDefaults { defaults in
            defaults.set("x", forKey: "k")
            defaults.synchronize()
        }
        let preferences = NSHomeDirectory() + "/Library/Preferences"
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: preferences))?
            .filter { $0.hasPrefix("teletype.test") } ?? []
        #expect(leftovers.isEmpty, "left behind: \(leftovers)")
    }
}
