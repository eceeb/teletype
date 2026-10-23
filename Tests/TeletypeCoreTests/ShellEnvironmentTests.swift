import Testing
@testable import TeletypeCore

struct ShellEnvironmentTests {
    @Test func announcesA256ColorXterm() {
        let environment = ShellEnvironment.make(from: [:])
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["TERM_PROGRAM"] == "Teletype")
    }

    @Test func announcesTruecolorSupport() {
        // bat, delta and nvim check COLORTERM before using 24-bit color; without
        // it they quantize to the 256-color palette and gradients look flat.
        #expect(ShellEnvironment.make(from: [:])["COLORTERM"] == "truecolor")
    }

    @Test func replacesWhateverTheAppInherited() {
        // A GUI app can inherit a TERM from however it was launched; the child
        // must see ours, not that.
        let environment = ShellEnvironment.make(from: ["TERM": "dumb"])
        #expect(environment["TERM"] == "xterm-256color")
    }

    @Test func keepsEverythingElseUntouched() {
        let environment = ShellEnvironment.make(from: ["PATH": "/usr/bin", "LANG": "de_DE.UTF-8"])
        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["LANG"] == "de_DE.UTF-8")
    }
}
