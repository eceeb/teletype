import SwiftTerm

/// A 24-bit RGB color. UI-neutral so the core stays free of AppKit.
public struct TermColor: Equatable, Sendable {
    public let red, green, blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// One fully-resolved grid cell ready to draw: character, colors (inverse
/// already applied), column width and styling.
public struct TerminalCell: Equatable, Sendable {
    public let character: Character
    public let foreground: TermColor
    public let background: TermColor
    /// Columns the glyph spans: 1, or 2 for wide glyphs; 0 = trailing half of a wide glyph.
    public let width: Int
    public let bold: Bool
    public let underline: Bool
}

/// Resolves SwiftTerm's color model into concrete RGB values — i.e. the theme.
/// Internal for now; later the settings can swap palettes.
struct TerminalPalette: Sendable {
    let defaultForeground: TermColor
    let defaultBackground: TermColor
    private let ansi: [TermColor]   // 256 entries (16 base + 216 cube + 24 gray)

    static let standard = TerminalPalette()

    init(
        defaultForeground: TermColor = TermColor(red: 229, green: 229, blue: 229),
        defaultBackground: TermColor = TermColor(red: 0, green: 0, blue: 0)
    ) {
        self.defaultForeground = defaultForeground
        self.defaultBackground = defaultBackground
        self.ansi = TerminalPalette.makeAnsi256()
    }

    func color(for color: Attribute.Color, isForeground: Bool) -> TermColor {
        switch color {
        case .ansi256(let code):
            return ansi[Int(code)]
        case .trueColor(let r, let g, let b):
            return TermColor(red: r, green: g, blue: b)
        case .defaultColor, .defaultInvertedColor:
            return isForeground ? defaultForeground : defaultBackground
        }
    }

    private static func makeAnsi256() -> [TermColor] {
        var colors: [TermColor] = [
            TermColor(red: 0,   green: 0,   blue: 0),    //  0 black
            TermColor(red: 205, green: 0,   blue: 0),    //  1 red
            TermColor(red: 0,   green: 205, blue: 0),    //  2 green
            TermColor(red: 205, green: 205, blue: 0),    //  3 yellow
            TermColor(red: 0,   green: 0,   blue: 238),  //  4 blue
            TermColor(red: 205, green: 0,   blue: 205),  //  5 magenta
            TermColor(red: 0,   green: 205, blue: 205),  //  6 cyan
            TermColor(red: 229, green: 229, blue: 229),  //  7 white
            TermColor(red: 127, green: 127, blue: 127),  //  8 bright black
            TermColor(red: 255, green: 0,   blue: 0),    //  9 bright red
            TermColor(red: 0,   green: 255, blue: 0),    // 10 bright green
            TermColor(red: 255, green: 255, blue: 0),    // 11 bright yellow
            TermColor(red: 92,  green: 92,  blue: 255),  // 12 bright blue
            TermColor(red: 255, green: 0,   blue: 255),  // 13 bright magenta
            TermColor(red: 0,   green: 255, blue: 255),  // 14 bright cyan
            TermColor(red: 255, green: 255, blue: 255),  // 15 bright white
        ]
        // 216-color cube (indices 16…231)
        let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    colors.append(TermColor(red: levels[r], green: levels[g], blue: levels[b]))
                }
            }
        }
        // Grayscale ramp (indices 232…255)
        for i in 0..<24 {
            let v = UInt8(8 + i * 10)
            colors.append(TermColor(red: v, green: v, blue: v))
        }
        return colors
    }
}
