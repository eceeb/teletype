import Testing
@testable import TeletypeCore

/// Comparing released versions, so the app can tell whether what it was built
/// against has been superseded.
struct VersionTests {
    @Test func itParsesAPlainVersion() {
        let version = Version("1.20.0")
        #expect(version?.major == 1)
        #expect(version?.minor == 20)
        #expect(version?.patch == 0)
    }

    @Test func aLeadingVIsAccepted() {
        // GitHub tags are usually "v1.99.1".
        #expect(Version("v1.99.1") == Version("1.99.1"))
    }

    @Test func missingComponentsCountAsZero() {
        #expect(Version("2") == Version("2.0.0"))
        #expect(Version("2.1") == Version("2.1.0"))
    }

    @Test func nonsenseIsNotAVersion() {
        #expect(Version("") == nil)
        #expect(Version("nightly") == nil)
    }

    @Test func componentsAreComparedAsNumbersNotText() {
        // The bug every hand-rolled comparison has: "1.9" must be below "1.20".
        #expect(Version("1.9.0")! < Version("1.20.0")!)
        #expect(Version("1.20.0")! < Version("1.99.1")!)
        #expect(Version("1.99.1")! < Version("2.0.0")!)
    }

    @Test func equalVersionsAreNotNewer() {
        #expect((Version("1.20.0")! < Version("1.20.0")!) == false)
    }

    @Test func aPreReleaseTagIsIgnored() {
        // "1.21.0-beta.1" is close enough to 1.21.0 for "is there something
        // newer?"; we are not resolving dependencies here.
        #expect(Version("1.21.0-beta.1")?.minor == 21)
    }

    // MARK: - What the check reports

    @Test func aHigherVersionIsAnUpdate() {
        let status = UpdateStatus(current: Version("1.20.0")!, latest: Version("1.99.1")!)
        #expect(status.hasUpdate)
        #expect(status.isMajorStep == false)   // same major, so a safe-ish bump
    }

    @Test func aMajorStepIsFlaggedSeparately() {
        // Worth knowing before pulling it in: the API may well have changed.
        let status = UpdateStatus(current: Version("1.99.1")!, latest: Version("2.0.0")!)
        #expect(status.hasUpdate)
        #expect(status.isMajorStep)
    }

    @Test func beingUpToDateIsNotAnUpdate() {
        let status = UpdateStatus(current: Version("1.20.0")!, latest: Version("1.20.0")!)
        #expect(status.hasUpdate == false)
    }

    @Test func anOlderPublishedVersionIsNotAnUpdate() {
        // Building against an unreleased revision shouldn't suggest going back.
        let status = UpdateStatus(current: Version("2.0.0")!, latest: Version("1.99.1")!)
        #expect(status.hasUpdate == false)
    }

    @Test func itDescribesItselfForTheUI() {
        let status = UpdateStatus(current: Version("1.20.0")!, latest: Version("1.99.1")!)
        #expect(status.summary == "1.20.0 → 1.99.1")
        let current = UpdateStatus(current: Version("1.20.0")!, latest: Version("1.20.0")!)
        #expect(current.summary == "1.20.0 (up to date)")
    }
}
