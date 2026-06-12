import Foundation

/// A named color profile: background, foreground and the 16 ANSI colors.
/// Values sourced from the iTerm2-Color-Schemes project (Windows Terminal format).
public struct ColorTheme: Sendable, Equatable {
    public let name: String
    public let background: TermColor
    public let foreground: TermColor
    /// 16 ANSI colors, in order 0…15 (black, red, green, yellow, blue, magenta,
    /// cyan, white, then the bright variants).
    public let ansi: [TermColor]

    public init(name: String, background: String, foreground: String, ansi: [String]) {
        self.name = name
        self.background = TermColor(hex: background)
        self.foreground = TermColor(hex: foreground)
        self.ansi = ansi.map { TermColor(hex: $0) }
    }

    /// Looks up a bundled theme by name (nil name or no match → nil = use the default palette).
    public static func named(_ name: String?) -> ColorTheme? {
        guard let name else { return nil }
        return all.first { $0.name == name }
    }

    public static let all: [ColorTheme] = [
        ColorTheme(name: "Dracula", background: "#282a36", foreground: "#f8f8f2",
                   ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                          "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]),
        ColorTheme(name: "Nord", background: "#2e3440", foreground: "#d8dee9",
                   ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                          "#596377", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]),
        ColorTheme(name: "Gruvbox Dark", background: "#282828", foreground: "#ebdbb2",
                   ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                          "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]),
        ColorTheme(name: "Solarized Dark", background: "#002b36", foreground: "#839496",
                   ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                          "#335e69", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        ColorTheme(name: "Solarized Light", background: "#fdf6e3", foreground: "#657b83",
                   ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#bbb5a2",
                          "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        ColorTheme(name: "Tokyo Night", background: "#1a1b26", foreground: "#c0caf5",
                   ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                          "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]),
        ColorTheme(name: "Catppuccin Mocha", background: "#1e1e2e", foreground: "#cdd6f4",
                   ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
                          "#585b70", "#f37799", "#89d88b", "#ebd391", "#74a8fc", "#f2aede", "#6bd7ca", "#bac2de"]),
        ColorTheme(name: "Catppuccin Latte", background: "#eff1f5", foreground: "#4c4f69",
                   ansi: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
                          "#6c6f85", "#de293e", "#49af3d", "#eea02d", "#456eff", "#fe85d8", "#2d9fa8", "#bcc0cc"]),
        ColorTheme(name: "One Half Dark", background: "#282c34", foreground: "#dcdfe4",
                   ansi: ["#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#dcdfe4",
                          "#5d677a", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#dcdfe4"]),
        ColorTheme(name: "Night Owl", background: "#011627", foreground: "#d6deeb",
                   ansi: ["#011627", "#ef5350", "#22da6e", "#addb67", "#82aaff", "#c792ea", "#21c7a8", "#ffffff",
                          "#575656", "#ef5350", "#22da6e", "#ffeb95", "#82aaff", "#c792ea", "#7fdbca", "#ffffff"]),
        ColorTheme(name: "Cobalt2", background: "#132738", foreground: "#ffffff",
                   ansi: ["#000000", "#ff0000", "#38de21", "#ffe50a", "#1460d2", "#ff005d", "#00bbbb", "#bbbbbb",
                          "#555555", "#f40e17", "#3bd01d", "#edc809", "#5555ff", "#ff55ff", "#6ae3fa", "#ffffff"]),
        ColorTheme(name: "Monokai", background: "#2d2a2e", foreground: "#fcfcfa",
                   ansi: ["#2d2a2e", "#ff6188", "#a9dc76", "#ffd866", "#fc9867", "#ab9df2", "#78dce8", "#fcfcfa",
                          "#727072", "#ff6188", "#a9dc76", "#ffd866", "#fc9867", "#ab9df2", "#78dce8", "#fcfcfa"]),
        ColorTheme(name: "Ayu Mirage", background: "#1f2430", foreground: "#cccac2",
                   ansi: ["#171b24", "#ed8274", "#87d96c", "#facc6e", "#6dcbfa", "#dabafa", "#90e1c6", "#c7c7c7",
                          "#686868", "#f28779", "#d5ff80", "#ffd173", "#73d0ff", "#dfbfff", "#95e6cb", "#ffffff"])
    ]
}
