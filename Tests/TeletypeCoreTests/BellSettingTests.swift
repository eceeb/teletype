import Testing
import Foundation
@testable import TeletypeCore

struct BellSettingTests {
    private func settings() -> TerminalSettings {
        let suite = UserDefaults(suiteName: "bell-test-\(UUID().uuidString)")!
        return TerminalSettings(defaults: suite)
    }

    @Test func theBellStaysSilentUntilTurnedOn() {
        // Teletype has always ignored BEL; switching it on is the user's call,
        // not something a new version should start doing by itself.
        #expect(settings().bellStyle == .none)
    }

    @Test func theChoiceIsRemembered() {
        let store = settings()
        store.bellStyle = .sound
        #expect(store.bellStyle == .sound)
        store.bellStyle = .visual
        #expect(store.bellStyle == .visual)
    }

    @Test func anUnknownStoredValueFallsBackToSilence() {
        let suite = UserDefaults(suiteName: "bell-bad-\(UUID().uuidString)")!
        suite.set("nonsense", forKey: "bellStyle")   // an older build, or a hand-edited plist
        #expect(TerminalSettings(defaults: suite).bellStyle == .none)
    }
}
