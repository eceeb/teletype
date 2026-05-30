import Testing
import Foundation
@testable import TeletypeCore

struct CellColorTests {
    /// Feeds bytes into a fresh emulator and returns the top-left cell.
    private func firstCell(after bytes: String) -> TerminalCell? {
        let term = TerminalEmulator(columns: 80, rows: 24)
        term.feed(Data(bytes.utf8))
        return term.cell(row: 0, col: 0)
    }

    @Test func plainTextUsesDefaultColors() {
        let cell = firstCell(after: "A")
        #expect(cell?.character == "A")
        #expect(cell?.foreground == TerminalPalette.standard.defaultForeground)
        #expect(cell?.background == TerminalPalette.standard.defaultBackground)
    }

    @Test func ansiForegroundColor() {
        // SGR 31 = red foreground (ANSI index 1)
        #expect(firstCell(after: "\u{1b}[31mX")?.foreground == TermColor(red: 205, green: 0, blue: 0))
    }

    @Test func extended256CubeAndGrayscale() {
        // 38;5;N selects from the 256-color palette.
        #expect(firstCell(after: "\u{1b}[38;5;231mX")?.foreground == TermColor(red: 255, green: 255, blue: 255))
        #expect(firstCell(after: "\u{1b}[38;5;232mX")?.foreground == TermColor(red: 8, green: 8, blue: 8))
    }

    @Test func trueColorForeground() {
        // 38;2;r;g;b selects a 24-bit color.
        #expect(firstCell(after: "\u{1b}[38;2;10;20;30mX")?.foreground == TermColor(red: 10, green: 20, blue: 30))
    }

    @Test func inverseSwapsForegroundAndBackground() {
        // SGR 7 = inverse: default fg/bg should be swapped.
        let cell = firstCell(after: "\u{1b}[7mZ")
        #expect(cell?.foreground == TerminalPalette.standard.defaultBackground)
        #expect(cell?.background == TerminalPalette.standard.defaultForeground)
    }
}
