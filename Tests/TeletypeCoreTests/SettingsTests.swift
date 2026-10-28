import Testing
import Foundation
@testable import TeletypeCore

struct SettingsTests {
    @Test func providesDefaults() {
        withTemporaryDefaults { defaults in
            let settings = TerminalSettings(defaults: defaults)
            #expect(settings.fontSize == 13)
            #expect(settings.backgroundColor == TermColor(red: 0, green: 0, blue: 0))
            #expect(settings.shell == nil)
        }
    }

    @Test func persistsAcrossInstances() {
        withTemporaryDefaults { defaults in
            let settings = TerminalSettings(defaults: defaults)
            settings.fontSize = 16
            settings.backgroundColor = TermColor(red: 10, green: 20, blue: 30)
            settings.shell = "/bin/bash"

            let reloaded = TerminalSettings(defaults: defaults)
            #expect(reloaded.fontSize == 16)
            #expect(reloaded.backgroundColor == TermColor(red: 10, green: 20, blue: 30))
            #expect(reloaded.shell == "/bin/bash")
        }
    }
}
