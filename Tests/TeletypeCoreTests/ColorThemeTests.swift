import Testing
@testable import TeletypeCore

@Test func termColorParsesHex() {
    #expect(TermColor(hex: "#50fa7b") == TermColor(red: 0x50, green: 0xfa, blue: 0x7b))
    #expect(TermColor(hex: "ff0000") == TermColor(red: 255, green: 0, blue: 0))   // # optional
    #expect(TermColor(hex: "#000000") == TermColor(red: 0, green: 0, blue: 0))
}

@Test func themeLookupByName() {
    #expect(ColorTheme.named(nil) == nil)
    #expect(ColorTheme.named("Does Not Exist") == nil)
    let dracula = ColorTheme.named("Dracula")
    #expect(dracula?.background == TermColor(hex: "#282a36"))
    #expect(dracula?.foreground == TermColor(hex: "#f8f8f2"))
    #expect(dracula?.ansi.first == TermColor(hex: "#21222c"))   // ANSI 0 = black
}

@Test func everyBundledThemeIsWellFormed() {
    #expect(!ColorTheme.all.isEmpty)
    for theme in ColorTheme.all {
        #expect(theme.ansi.count == 16, "\(theme.name) needs exactly 16 ANSI colors")
        #expect(!theme.name.isEmpty)
    }
}

@Test func themeNamesAreUnique() {
    let names = ColorTheme.all.map(\.name)
    #expect(Set(names).count == names.count)
}
