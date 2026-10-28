import Testing
@testable import TeletypeCore

/// The one-line form shown at the bottom of the sidebar.
struct UpdateNoticeTests {
    private func update(_ name: String, _ from: String, _ to: String) -> DependencyUpdate {
        DependencyUpdate(
            dependency: Dependency(name: name, repository: "x/\(name)", current: Version(from)!),
            status: UpdateStatus(current: Version(from)!, latest: Version(to)!),
            failed: false)
    }

    @Test func nothingToSayWhenEverythingIsCurrent() {
        #expect(UpdateNotice.text(for: []) == nil)
    }

    @Test func oneUpdateNamesTheLibraryAndItsNewVersion() {
        let notice = UpdateNotice.text(for: [update("SwiftTerm", "1.20.0", "1.99.1")])
        #expect(notice?.title == "SwiftTerm 1.99.1")
        #expect(notice?.detail == "Update available")
    }

    @Test func severalUpdatesAreCounted() {
        let notice = UpdateNotice.text(for: [
            update("SwiftTerm", "1.20.0", "1.99.1"),
            update("swift-argument-parser", "1.8.2", "1.9.0")
        ])
        #expect(notice?.title == "2 library updates")
        #expect(notice?.detail == "Update available")
    }

    @Test func aMajorStepSaysSo() {
        // Worth seeing before you pull it in: the API may have changed.
        let notice = UpdateNotice.text(for: [update("SwiftTerm", "1.99.1", "2.0.0")])
        #expect(notice?.detail == "New major version")
    }

    @Test func aMajorStepAmongSeveralStillWins() {
        let notice = UpdateNotice.text(for: [
            update("swift-argument-parser", "1.8.2", "1.9.0"),
            update("SwiftTerm", "1.99.1", "2.0.0")
        ])
        #expect(notice?.detail == "New major version")
    }
}
