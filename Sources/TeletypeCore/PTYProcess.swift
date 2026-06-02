import Foundation
import Darwin
import CPTY

/// Errors thrown while setting up a pseudo-terminal child process.
public enum PTYError: Error {
    case openFailed(Int32)
    case spawnFailed(Int32)
}

/// Spawns a child process attached to a pseudo-terminal (PTY) and lets us
/// read its output and write input on the master end.
///
/// This is the lowest layer of the terminal: it knows nothing about escape
/// sequences or rendering — it just moves bytes to/from the child (e.g. zsh).
public final class PTYProcess {
    /// File descriptor of the master end. `-1` until `start` succeeds.
    public private(set) var masterFD: Int32 = -1
    /// PID of the spawned child. `-1` until `start` succeeds.
    public private(set) var pid: pid_t = -1

    public init() {}

    public func start(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        // 1. Open a PTY master/slave pair (pure POSIX — no <util.h> needed).
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw PTYError.openFailed(errno) }
        guard grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            close(master)
            throw PTYError.openFailed(errno)
        }
        let slave = open(String(cString: name), O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            throw PTYError.openFailed(errno)
        }

        // 2. Build NULL-terminated argv / envp BEFORE forking, so the child does
        //    no Swift allocation between fork and exec.
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        // 3. Fork + exec via a tiny C helper (fork() is unavailable from Swift):
        //    it makes the slave the child's controlling terminal (setsid +
        //    TIOCSCTTY) so Ctrl-C / Ctrl-Z and job control work.
        let childPID = cpty_spawn(slave, master, argv, envp)

        // 4. Parent keeps only the master end.
        close(slave)
        guard childPID > 0 else {
            close(master)
            throw PTYError.spawnFailed(errno)
        }
        masterFD = master
        pid = childPID
    }

    /// Writes input bytes to the child via the master end.
    public func write(_ data: Data) {
        guard masterFD >= 0, !data.isEmpty else { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            _ = Darwin.write(masterFD, raw.baseAddress, raw.count)
        }
    }

    /// Reads currently-available output.
    ///
    /// - Parameter timeoutMillis: how long to wait for data. `-1` (default)
    ///   blocks until bytes arrive or EOF. `>= 0` waits at most that many
    ///   milliseconds, then returns empty `Data` if nothing showed up — so a
    ///   silent child can never block the caller forever.
    /// - Returns: the bytes read, or empty `Data` on timeout / EOF.
    public func read(timeoutMillis: Int32 = -1) -> Data {
        guard masterFD >= 0 else { return Data() }
        if timeoutMillis >= 0 {
            var pfd = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, nfds_t(1), timeoutMillis) > 0,
                  (pfd.revents & Int16(POLLIN)) != 0 else { return Data() }
        }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(masterFD, raw.baseAddress, raw.count)
        }
        guard n > 0 else { return Data() }
        return Data(buffer.prefix(n))
    }

    /// Tells the PTY (and thus the child) the terminal size in characters, so
    /// full-screen programs lay themselves out correctly.
    public func setWindowSize(columns: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var size = winsize(ws_row: UInt16(max(0, rows)),
                           ws_col: UInt16(max(0, columns)),
                           ws_xpixel: 0,
                           ws_ypixel: 0)
        _ = withUnsafeMutablePointer(to: &size) { pointer in
            ioctl(masterFD, UInt(TIOCSWINSZ), pointer)
        }
    }

    /// Asks the child to terminate.
    public func terminate() {
        if pid > 0 { kill(pid, SIGTERM) }
    }
}
