import Testing
import Foundation
@testable import TeletypeCore

struct PTYProcessTests {
    @Test func spawnsCommandAndReadsItsOutput() throws {
        let pty = PTYProcess()
        try pty.start(executable: "/bin/echo", arguments: ["hello"])

        var output = Data()
        while true {
            let chunk = pty.read()
            if chunk.isEmpty { break }   // EOF: child exited, slave closed
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
