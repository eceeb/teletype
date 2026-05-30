import Foundation
import Darwin

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

        // 2. Wire the child's stdin/stdout/stderr to the slave end,
        //    and close the raw fds the child shouldn't keep.
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, slave, 0)
        posix_spawn_file_actions_adddup2(&actions, slave, 1)
        posix_spawn_file_actions_adddup2(&actions, slave, 2)
        posix_spawn_file_actions_addclose(&actions, slave)
        posix_spawn_file_actions_addclose(&actions, master)
        defer { posix_spawn_file_actions_destroy(&actions) }

        // 3. New session so the PTY can act as the controlling terminal.
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, CShort(POSIX_SPAWN_SETSID))
        defer { posix_spawnattr_destroy(&attr) }

        // 4. Build NULL-terminated argv / envp C arrays.
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        // 5. Spawn. posix_spawn copies argv/envp during the call, so freeing
        //    them afterwards (via defer) is safe.
        var newPID: pid_t = 0
        let rc = posix_spawn(&newPID, executable, &actions, &attr, argv, envp)
        close(slave) // parent keeps only the master end
        guard rc == 0 else {
            close(master)
            throw PTYError.spawnFailed(rc)
        }
        masterFD = master
        pid = newPID
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

    /// Asks the child to terminate.
    public func terminate() {
        if pid > 0 { kill(pid, SIGTERM) }
    }
}
