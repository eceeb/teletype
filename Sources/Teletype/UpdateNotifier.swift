import AppKit
import TeletypeCore

/// Runs the dependency check and tells the user about it.
///
/// Deliberately quiet: on launch it only speaks up when something is actually
/// newer, at most once a day. Asked explicitly (Shell → Check for Updates…) it
/// always reports, including "everything is current".
@MainActor
enum UpdateNotifier {
    private static let checkInterval: TimeInterval = 86_400   // once a day

    /// What the last background check found, for the menu item to show.
    private(set) static var pendingUpdates: [DependencyUpdate] = []
    /// Called when that changes, so the menu title can follow.
    static var onResult: (() -> Void)?

    /// Called at launch. Does nothing if the user switched the check off, or if
    /// it already ran today. Never interrupts — the result lands in the menu.
    static func checkInBackground() {
        if ProcessInfo.processInfo.arguments.contains("-probeUpdateNotice") {
            // For checking how the notice looks in a dev build, which has no
            // Info.plist and therefore no recorded versions to compare.
            pendingUpdates = [DependencyUpdate(
                dependency: Dependency(name: "SwiftTerm", repository: "migueldeicaza/SwiftTerm",
                                       current: Version("1.20.0")!),
                status: UpdateStatus(current: Version("1.20.0")!, latest: Version("1.99.1")!),
                failed: false)]
            onResult?()
            return
        }
        guard AppSettings.store.checksForUpdates else { return }
        guard UpdateChecker.shouldCheck(lastCheck: AppSettings.store.lastUpdateCheck,
                                        now: Date(), interval: checkInterval) else { return }
        Task { await run(announceWhenCurrent: false) }
    }

    /// Called from the menu: always reports, even when there is nothing to do.
    static func checkNow() {
        Task { await run(announceWhenCurrent: true) }
    }

    private static func run(announceWhenCurrent: Bool) async {
        let dependencies = DependencyVersions.builtAgainst()
        guard !dependencies.isEmpty else {
            if announceWhenCurrent { report(title: "No version information",
                                            body: "This build has no recorded dependency versions. Reinstall with packaging/install.sh.") }
            return
        }

        let checker = UpdateChecker { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            // GitHub wants a User-Agent, and asks for this Accept header.
            request.setValue("Teletype", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }
        let results = await checker.check(dependencies)
        AppSettings.store.lastUpdateCheck = Date()

        let updates = results.filter { $0.status?.hasUpdate == true }
        pendingUpdates = updates
        onResult?()

        // A launch-time check stays silent either way: the menu now says what
        // it found, and a dialog on every start until you get round to updating
        // would just train you to dismiss it.
        guard announceWhenCurrent else { return }

        guard updates.isEmpty == false else {
            guard announceWhenCurrent else { return }
            let failed = results.filter(\.failed)
            if failed.isEmpty {
                let lines = results.compactMap { result -> String? in
                    guard let status = result.status else { return nil }
                    return "\(result.dependency.name) \(status.summary)"
                }
                report(title: "Everything is current", body: lines.joined(separator: "\n"))
            } else {
                report(title: "Couldn't check",
                       body: "No answer for: " + failed.map(\.dependency.name).joined(separator: ", "))
            }
            return
        }

        let lines = updates.map { update -> String in
            let marker = update.status?.isMajorStep == true ? "  (new major version)" : ""
            return "\(update.dependency.name) \(update.status?.summary ?? "")\(marker)"
        }
        report(title: updates.count == 1 ? "An update is available" : "Updates are available",
               body: lines.joined(separator: "\n")
                   + "\n\nTo pull them in:\n  swift package update\n  swift test\n  bash packaging/install.sh")
    }

    private static func report(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
