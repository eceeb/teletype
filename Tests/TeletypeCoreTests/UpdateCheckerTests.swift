import Testing
import Foundation
@testable import TeletypeCore

/// Asking GitHub what the newest release of each dependency is.
struct UpdateCheckerTests {
    private let swiftTerm = Dependency(name: "SwiftTerm",
                                       repository: "migueldeicaza/SwiftTerm",
                                       current: Version("1.20.0")!)

    private func release(_ tag: String) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"https://example.com/r"}"#.utf8)
    }

    @Test func itReportsAnAvailableUpdate() async {
        let checker = UpdateChecker { _ in self.release("v1.99.1") }
        let results = await checker.check([swiftTerm])

        #expect(results.count == 1)
        #expect(results[0].status?.hasUpdate == true)
        #expect(results[0].status?.latest == Version("1.99.1"))
    }

    @Test func itReportsBeingCurrent() async {
        let checker = UpdateChecker { _ in self.release("v1.20.0") }
        let results = await checker.check([swiftTerm])
        #expect(results[0].status?.hasUpdate == false)
    }

    @Test func aFailedRequestIsReportedAsUnknownNotAsUpToDate() async {
        // Offline must not look like "nothing new" — that would quietly hide
        // updates for as long as the network is down.
        struct Boom: Error {}
        let checker = UpdateChecker { _ in throw Boom() }
        let results = await checker.check([swiftTerm])
        #expect(results[0].status == nil)
        #expect(results[0].failed)
    }

    @Test func anUnparsableTagIsAlsoUnknown() async {
        let checker = UpdateChecker { _ in Data(#"{"tag_name":"nightly"}"#.utf8) }
        let results = await checker.check([swiftTerm])
        #expect(results[0].status == nil)
    }

    /// Records what URL the checker asked for, across the concurrency boundary.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var value: URL?
        func record(_ url: URL) { lock.lock(); value = url; lock.unlock() }
        var url: URL? { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test func itAsksTheRightURL() async {
        let recorder = Recorder()
        let checker = UpdateChecker { url in
            recorder.record(url)
            return self.release("v1.20.0")
        }
        _ = await checker.check([swiftTerm])
        #expect(recorder.url?.absoluteString
            == "https://api.github.com/repos/migueldeicaza/SwiftTerm/releases/latest")
    }

    @Test func everyDependencyIsChecked() async {
        let other = Dependency(name: "swift-argument-parser",
                               repository: "apple/swift-argument-parser",
                               current: Version("1.8.2")!)
        let checker = UpdateChecker { _ in self.release("v9.9.9") }
        let results = await checker.check([swiftTerm, other])
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status?.hasUpdate == true })
    }

    // MARK: - How often

    @Test func theFirstCheckAlwaysRuns() {
        #expect(UpdateChecker.shouldCheck(lastCheck: nil, now: Date(), interval: 86_400))
    }

    @Test func itWaitsOutTheInterval() {
        let now = Date()
        let anHourAgo = now.addingTimeInterval(-3_600)
        #expect(UpdateChecker.shouldCheck(lastCheck: anHourAgo, now: now, interval: 86_400) == false)

        let twoDaysAgo = now.addingTimeInterval(-172_800)
        #expect(UpdateChecker.shouldCheck(lastCheck: twoDaysAgo, now: now, interval: 86_400))
    }

    @Test func aClockThatWentBackwardsStillChecks() {
        // A stored date in the future (clock change, restored backup) must not
        // lock the check out forever.
        let now = Date()
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(UpdateChecker.shouldCheck(lastCheck: tomorrow, now: now, interval: 86_400))
    }
}
