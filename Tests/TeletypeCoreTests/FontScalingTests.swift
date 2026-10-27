import Testing
@testable import TeletypeCore

/// ⌘+ / ⌘− / ⌘0 for the terminal font.
struct FontScalingTests {
    @Test func steppingUpAndDownMovesOnePoint() {
        #expect(FontScaling.stepped(13, by: 1) == 14)
        #expect(FontScaling.stepped(13, by: -1) == 12)
    }

    @Test func itStopsAtTheSameBoundsAsTheSettingsSlider() {
        #expect(FontScaling.stepped(FontScaling.maximum, by: 1) == FontScaling.maximum)
        #expect(FontScaling.stepped(FontScaling.minimum, by: -1) == FontScaling.minimum)
    }

    @Test func anOutOfRangeStoredSizeIsPulledBackIn() {
        // Settings could hold anything from an older build or a hand-edited plist.
        #expect(FontScaling.stepped(999, by: 1) == FontScaling.maximum)
        #expect(FontScaling.stepped(0, by: -1) == FontScaling.minimum)
    }

    @Test func resetReturnsTheDefaultSize() {
        #expect(FontScaling.defaultSize == 13)
    }

    @Test func fractionalSizesSnapToWholePoints() {
        // The slider steps by 1, so the keyboard must not leave 13.5 behind.
        #expect(FontScaling.stepped(13.5, by: 1) == 14)
        #expect(FontScaling.stepped(13.5, by: -1) == 13)
    }
}
