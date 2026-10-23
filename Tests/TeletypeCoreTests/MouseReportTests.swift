import Testing
@testable import TeletypeCore

/// xterm's Cb button byte, and which events a tracking mode actually wants.
/// Bits: 0-1 button, 4 shift, 8 meta, 16 control, 32 motion, 64 wheel.
struct MouseReportTests {
    @Test func buttonsUseTheLowTwoBits() {
        #expect(MouseReport.buttonFlags(.press, button: .left, modifiers: []) == 0)
        #expect(MouseReport.buttonFlags(.press, button: .middle, modifiers: []) == 1)
        #expect(MouseReport.buttonFlags(.press, button: .right, modifiers: []) == 2)
    }

    @Test func releaseIsButtonThree() {
        // SwiftTerm turns "low bits == 3, no motion" into SGR's lowercase m.
        #expect(MouseReport.buttonFlags(.release, button: .left, modifiers: []) == 3)
        #expect(MouseReport.buttonFlags(.release, button: .right, modifiers: []) == 3)
    }

    @Test func modifiersAddTheirBits() {
        #expect(MouseReport.buttonFlags(.press, button: .left, modifiers: .shift) == 4)
        #expect(MouseReport.buttonFlags(.press, button: .left, modifiers: .option) == 8)
        #expect(MouseReport.buttonFlags(.press, button: .left, modifiers: .control) == 16)
        #expect(MouseReport.buttonFlags(.press, button: .right,
                                        modifiers: [.shift, .control]) == 2 + 4 + 16)
    }

    @Test func draggingSetsTheMotionBit() {
        #expect(MouseReport.buttonFlags(.drag, button: .left, modifiers: []) == 32)
        #expect(MouseReport.buttonFlags(.drag, button: .right, modifiers: []) == 34)
    }

    @Test func motionWithNoButtonHeldIsThreePlusMotion() {
        #expect(MouseReport.buttonFlags(.motion, button: .left, modifiers: []) == 35)
    }

    @Test func theWheelUsesBitSix() {
        #expect(MouseReport.buttonFlags(.scrollUp, button: .left, modifiers: []) == 64)
        #expect(MouseReport.buttonFlags(.scrollDown, button: .left, modifiers: []) == 65)
        #expect(MouseReport.buttonFlags(.scrollUp, button: .left, modifiers: .shift) == 68)
    }

    @Test func offReportsNothing() {
        for kind in MouseEventKind.allCases {
            #expect(MouseReport.shouldReport(kind, tracking: .off) == false)
        }
    }

    @Test func x10ReportsOnlyPresses() {
        #expect(MouseReport.shouldReport(.press, tracking: .pressOnly))
        #expect(MouseReport.shouldReport(.release, tracking: .pressOnly) == false)
        #expect(MouseReport.shouldReport(.drag, tracking: .pressOnly) == false)
    }

    @Test func vt200AddsReleasesButNotMotion() {
        #expect(MouseReport.shouldReport(.press, tracking: .pressAndRelease))
        #expect(MouseReport.shouldReport(.release, tracking: .pressAndRelease))
        #expect(MouseReport.shouldReport(.drag, tracking: .pressAndRelease) == false)
        #expect(MouseReport.shouldReport(.motion, tracking: .pressAndRelease) == false)
    }

    @Test func buttonTrackingAddsDragButNotFreeMotion() {
        #expect(MouseReport.shouldReport(.drag, tracking: .withDrag))
        #expect(MouseReport.shouldReport(.motion, tracking: .withDrag) == false)
    }

    @Test func anyEventTracksEverything() {
        for kind in MouseEventKind.allCases {
            #expect(MouseReport.shouldReport(kind, tracking: .anyMotion))
        }
    }

    @Test func theWheelIsReportedInEveryTrackingMode() {
        // Scrolling a pager through mouse reports is the common case; even X10
        // apps expect wheel events once they asked for tracking at all.
        for tracking in [MouseTracking.pressOnly, .pressAndRelease, .withDrag, .anyMotion] {
            #expect(MouseReport.shouldReport(.scrollUp, tracking: tracking))
            #expect(MouseReport.shouldReport(.scrollDown, tracking: tracking))
        }
    }
}
