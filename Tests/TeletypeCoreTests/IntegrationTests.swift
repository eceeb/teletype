import Testing
import Foundation
@testable import TeletypeCore

/// End-to-end across the two layers built so far: a real child process'
/// output, piped through the PTY and into the parser's grid.
struct IntegrationTests {
    @Test func pipesLivePTYOutputIntoTheGrid() throws {
        let pty = PTYProcess()
        try pty.start(executable: "/bin/echo", arguments: ["hi"])
        let term = TerminalEmulator()

        while true {
            let chunk = pty.read(timeoutMillis: 1000)
            if chunk.isEmpty { break }  // EOF / no more output
            term.feed(chunk)
        }

        #expect(term.line(0) == "hi")
    }
}
