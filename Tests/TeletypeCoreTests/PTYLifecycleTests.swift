import Testing
import Foundation
import Darwin
@testable import TeletypeCore

/// Covers the part of `PTYProcess` that isn't about moving bytes: spawning a
/// child into its own session, and tearing it down without leaving a zombie
/// process or a leaked pseudo-terminal behind.
struct PTYLifecycleTests {

    // MARK: - Helpers

    /// Polls `condition` until it holds or the budget runs out. Everything here
    /// crosses a process boundary, so nothing is observable synchronously: the
    /// child still has to reach `setsid`, and the reap happens off-thread.
    private func eventually(within seconds: Double = 2,
                            _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            usleep(5_000)
        }
        return condition()
    }

    /// Number of open file descriptors in this process — the only way to see a
    /// PTY leak from the outside.
    private func openFileDescriptorCount() -> Int {
        var count = 0
        for fd in 0..<Int32(getdtablesize()) where fcntl(fd, F_GETFD) != -1 {
            count += 1
        }
        return count
    }

    /// A long-lived child that won't exit on its own and reacts to SIGTERM.
    private func startSleeper() throws -> PTYProcess {
        let pty = PTYProcess()
        try pty.start(executable: "/bin/sleep", arguments: ["30"])
        return pty
    }

    // MARK: - Start

    @Test func startPublishesTheChildPIDAndMasterFD() throws {
        let pty = try startSleeper()
        defer { pty.terminate() }

        #expect(pty.pid > 0)
        #expect(pty.masterFD >= 0)
    }

    @Test func theChildRunsInItsOwnSessionWithTheSlaveAsControllingTerminal() throws {
        let pty = try startSleeper()
        defer { pty.terminate() }

        // setsid() makes the child a session leader: its session id is its pid.
        #expect(eventually { getsid(pty.pid) == pty.pid })
        // tcgetpgrp on the master only answers once the slave really is the
        // child's controlling terminal (the TIOCSCTTY in cpty_spawn). Without
        // it job control is dead — Ctrl-C would hit nothing.
        #expect(eventually { tcgetpgrp(pty.masterFD) == pty.pid })
    }

    @Test func startsTheChildInTheRequestedWorkingDirectory() throws {
        let directory = NSTemporaryDirectory()
        let pty = PTYProcess()
        try pty.start(executable: "/bin/sleep", arguments: ["30"], workingDirectory: directory)
        defer { pty.terminate() }

        // Both sides through realpath: /tmp is a symlink to /private/tmp.
        let expected = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
        #expect(eventually {
            guard let cwd = pty.workingDirectory() else { return false }
            return URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path == expected
        })
    }

    @Test func aMissingExecutableLeavesNoUsableChild() throws {
        let pty = PTYProcess()
        // fork() succeeds, execve() doesn't — the child exits 127 right away.
        try pty.start(executable: "/nonexistent/teletype-does-not-exist")
        defer { pty.terminate() }

        #expect(eventually {
            var status: Int32 = 0
            return waitpid(pty.pid, &status, WNOHANG) == pty.pid
                && WIFEXITED(status) && WEXITSTATUS(status) == 127
        })
    }

    // MARK: - Terminate

    @Test func terminateReapsTheChild() throws {
        // Deliberately with SIGTERM blocked in this process: fork() hands the
        // mask to the child and execve() keeps it, so a child that didn't reset
        // it would never see the signal and would outlive its pane. (The test
        // runner blocks SIGTERM anyway — this just makes it explicit.)
        var blockTerm = sigset_t(), previous = sigset_t()
        sigemptyset(&blockTerm)
        sigaddset(&blockTerm, SIGTERM)
        sigprocmask(SIG_BLOCK, &blockTerm, &previous)
        defer { sigprocmask(SIG_SETMASK, &previous, nil) }

        let pty = try startSleeper()
        let child = pty.pid

        pty.terminate()

        // Reaped means waitpid can no longer find it: -1/ECHILD. A zombie would
        // still be waitable and answer with the pid instead — that was the bug.
        #expect(eventually {
            var status: Int32 = 0
            return waitpid(child, &status, WNOHANG) == -1 && errno == ECHILD
        })
    }

    @Test func terminateClosesTheMasterFD() throws {
        let pty = try startSleeper()
        let master = pty.masterFD

        pty.terminate()

        #expect(pty.masterFD == -1)
        #expect(fcntl(master, F_GETFD) == -1)   // really closed, not just forgotten
    }

    @Test func repeatedStartAndTerminateLeakNoFileDescriptors() throws {
        // One warm-up cycle first: the very first spawn can allocate lazily
        // (dyld, libproc), which would otherwise look like a leak.
        let warmup = try startSleeper()
        warmup.terminate()

        let before = openFileDescriptorCount()
        for _ in 0..<20 {
            let pty = try startSleeper()
            pty.terminate()
        }
        let after = openFileDescriptorCount()

        // Each leaked cycle would cost at least one fd; 20 cycles make a leak
        // unmissable. A couple of fds of slack keeps the test from being flaky.
        #expect(after - before <= 2, "leaked \(after - before) fds over 20 cycles")
    }

    @Test func terminateIsSafeToCallTwice() throws {
        let pty = try startSleeper()

        pty.terminate()
        pty.terminate()   // must not close fd -1, must not signal pid -1

        #expect(pty.masterFD == -1)
    }

    @Test func readAndWriteDoNothingAfterTerminate() throws {
        let pty = try startSleeper()
        pty.terminate()

        pty.write(Data("ignored\n".utf8))        // no crash, no write to a closed fd
        #expect(pty.read(timeoutMillis: 50).isEmpty)
    }

    @Test func setWindowSizeIsIgnoredAfterTerminate() throws {
        let pty = try startSleeper()
        pty.terminate()

        pty.setWindowSize(columns: 120, rows: 40)   // guard on masterFD, no crash
        #expect(pty.masterFD == -1)
    }

    @Test func queriesReturnNilOnAFreshProcess() {
        let pty = PTYProcess()   // never started: pid/masterFD are -1

        #expect(pty.workingDirectory() == nil)
        #expect(pty.foregroundProcessName() == nil)
        #expect(pty.read(timeoutMillis: 10).isEmpty)
    }

    @Test func theChildDoesNotInheritAnIgnoredSignal() throws {
        // Same inheritance trap on the disposition side: execve resets *caught*
        // signals to default but leaves SIG_IGN in place. A shell that inherits
        // an ignored SIGPIPE passes it on to everything the user starts, where
        // it breaks ordinary pipelines (`… | head` never gets to stop the
        // writer).
        var ignore = sigaction(), previous = sigaction()
        ignore.__sigaction_u.__sa_handler = SIG_IGN
        sigaction(SIGPIPE, &ignore, &previous)
        defer { sigaction(SIGPIPE, &previous, nil) }

        let pty = PTYProcess()
        try pty.start(executable: "/bin/sh", arguments: ["-c", "kill -PIPE $$"])
        defer { pty.terminate() }

        // With a default disposition the shell dies *from the signal*; with an
        // inherited SIG_IGN it shrugs it off and exits 0.
        var status: Int32 = 0
        #expect(eventually { waitpid(pty.pid, &status, WNOHANG) == pty.pid })
        #expect(WIFSIGNALED(status), "child exited normally — SIGPIPE was ignored")
        #expect(WTERMSIG(status) == SIGPIPE)
    }

    // MARK: - Window size

    @Test func setWindowSizeReachesTheChild() throws {
        let pty = PTYProcess()
        try pty.start(executable: "/bin/sh", arguments: ["-i"])
        defer { pty.terminate() }

        pty.setWindowSize(columns: 123, rows: 45)
        pty.write(Data("stty size\n".utf8))

        var output = ""
        _ = eventually {
            output += String(decoding: pty.read(timeoutMillis: 200), as: UTF8.self)
            return output.contains("45 123")
        }
        #expect(output.contains("45 123"), "stty reported: \(output)")
    }
}

// waitpid's status macros are C macros, so Swift doesn't import them.
private func WIFEXITED(_ status: Int32) -> Bool { (status & 0x7f) == 0 }
private func WEXITSTATUS(_ status: Int32) -> Int32 { (status >> 8) & 0xff }
private func WIFSIGNALED(_ status: Int32) -> Bool { (status & 0x7f) != 0 && (status & 0x7f) != 0x7f }
private func WTERMSIG(_ status: Int32) -> Int32 { status & 0x7f }
