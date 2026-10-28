import Testing
import Foundation
@testable import TeletypeCore

struct BellSettingTests {
    @Test func theBellStaysSilentUntilTurnedOn() {
        // Teletype has always ignored BEL; switching it on is the user's call,
        // not something a new version should start doing by itself.
        withTemporaryDefaults { defaults in
            #expect(TerminalSettings(defaults: defaults).bellStyle == .none)
        }
    }

    @Test func theChoiceIsRemembered() {
        withTemporaryDefaults { defaults in
            let store = TerminalSettings(defaults: defaults)
            store.bellStyle = .sound
            #expect(store.bellStyle == .sound)
            store.bellStyle = .visual
            #expect(store.bellStyle == .visual)
        }
    }

    @Test func anUnknownStoredValueFallsBackToSilence() {
        withTemporaryDefaults { defaults in
            defaults.set("nonsense", forKey: "bellStyle")   // an older build, or a hand-edited plist
            #expect(TerminalSettings(defaults: defaults).bellStyle == .none)
        }
    }
}
