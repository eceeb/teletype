import Testing
import Foundation
@testable import TeletypeCore

/// Emoji outside the Basic Multilingual Plane take two UTF-16 units and two
/// grid cells. They have to survive the parser intact.
struct EmojiCellTests {
    private func emulator() -> TerminalEmulator {
        TerminalEmulator(columns: 20, rows: 3)
    }

    @Test func anEmojiKeepsItsCharacter() {
        let terminal = emulator()
        terminal.feed(Data("🎉".utf8))
        #expect(terminal.cell(row: 0, col: 0)?.character == "🎉")
    }

    @Test func anEmojiIsTwoCellsWide() {
        let terminal = emulator()
        terminal.feed(Data("🎉".utf8))
        #expect(terminal.cell(row: 0, col: 0)?.width == 2)
        #expect(terminal.cell(row: 0, col: 1)?.width == 0)
    }

    @Test func textAfterAnEmojiKeepsItsColumn() {
        let terminal = emulator()
        terminal.feed(Data("🎉ok".utf8))
        #expect(terminal.cell(row: 0, col: 2)?.character == "o")
        #expect(terminal.cell(row: 0, col: 3)?.character == "k")
    }

    @Test func aCJKCharacterBehavesTheSame() {
        let terminal = emulator()
        terminal.feed(Data("漢x".utf8))
        #expect(terminal.cell(row: 0, col: 0)?.character == "漢")
        #expect(terminal.cell(row: 0, col: 2)?.character == "x")
    }
}
