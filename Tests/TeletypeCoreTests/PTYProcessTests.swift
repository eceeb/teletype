import Testing
import Foundation
@testable import TeletypeCore

struct PTYProcessTests {
    @Test func spawnsCommandAndReadsItsOutput() throws {
        let pty = PTYProcess()
        try pty.start(executable: "/bin/echo", arguments: ["hello"])
        defer { pty.terminate() }

        // Bounded read: PTY end-of-file on macOS is racy (EIO vs. block), so
        // never read blocking-without-timeout in a test.
        var output = Data()
        while true {
            let chunk = pty.read(timeoutMillis: 1000)
            if chunk.isEmpty { break }   // EOF or no more output
            output.append(chunk)
        }

        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("hello"))
    }

    @Test func writesInputAndReadsItBack() throws {
        let pty = PTYProcess()
        try pty.start(executable: "/bin/cat")  // cat mirrors stdin to stdout
        defer { pty.terminate() }

        pty.write(Data("ping\n".utf8))

        // The tty line discipline echoes input back on the master end. A
        // per-read timeout guarantees the test can never block forever.
        var output = Data()
        for _ in 0..<20 {
            output.append(pty.read(timeoutMillis: 200))
            if String(decoding: output, as: UTF8.self).contains("ping") { break }
        }

        #expect(String(decoding: output, as: UTF8.self).contains("ping"))
    }
}
