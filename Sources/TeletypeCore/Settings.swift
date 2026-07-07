import Foundation

/// User-configurable terminal settings, persisted in `UserDefaults`
/// (which is itself thread-safe, hence `@unchecked Sendable`).
public final class TerminalSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var fontSize: Double {
        get { defaults.object(forKey: Key.fontSize) as? Double ?? 13 }
        set { defaults.set(newValue, forKey: Key.fontSize) }
    }

    public var backgroundColor: TermColor {
        get { color(forKey: Key.background) ?? TermColor(red: 0, green: 0, blue: 0) }
        set { setColor(newValue, forKey: Key.background) }
    }

    public var foregroundColor: TermColor {
        get { color(forKey: Key.foreground) ?? TermColor(red: 229, green: 229, blue: 229) }
        set { setColor(newValue, forKey: Key.foreground) }
    }

    /// The shell to launch, or `nil` to use the user's login shell ($SHELL).
    public var shell: String? {
        get { defaults.string(forKey: Key.shell) }
        set { defaults.set(newValue, forKey: Key.shell) }
    }

    /// Tab bar placement: "top" or "left".
    public var tabPlacement: String {
        get { defaults.string(forKey: Key.tabPlacement) ?? "top" }
        set { defaults.set(newValue, forKey: Key.tabPlacement) }
    }

    /// Directory new tabs open in (tilde allowed); nil/empty → the user's home.
    public var newTabDirectory: String? {
        get { defaults.string(forKey: Key.newTabDirectory) }
        set { defaults.set(newValue, forKey: Key.newTabDirectory) }
    }

    /// Selected color theme name (nil → default palette + custom bg/fg).
    public var themeName: String? {
        get { defaults.string(forKey: Key.themeName) }
        set { defaults.set(newValue, forKey: Key.themeName) }
    }

    /// Mouse-wheel scroll multiplier (1 = one line per notch's worth of delta).
    public var scrollSpeed: Double {
        get { defaults.object(forKey: Key.scrollSpeed) as? Double ?? 3 }
        set { defaults.set(newValue, forKey: Key.scrollSpeed) }
    }

    /// Lines of scrollback each pane keeps (default 10_000; SwiftTerm's own
    /// default is only 500). Higher keeps more history but costs more memory.
    public var scrollbackLines: Int {
        get { defaults.object(forKey: Key.scrollbackLines) as? Int ?? 10_000 }
        set { defaults.set(newValue, forKey: Key.scrollbackLines) }
    }

    /// Path or name of the `claude` binary; nil/empty → auto-detect on PATH.
    public var claudeCommand: String? {
        get { defaults.string(forKey: Key.claudeCommand) }
        set { defaults.set(newValue, forKey: Key.claudeCommand) }
    }

    /// Selected app-icon id (a name from the icon catalog); nil → the default.
    public var appIconName: String? {
        get { defaults.string(forKey: Key.appIconName) }
        set { defaults.set(newValue, forKey: Key.appIconName) }
    }

    private func color(forKey key: String) -> TermColor? {
        guard let rgb = defaults.array(forKey: key) as? [Int], rgb.count == 3 else { return nil }
        return TermColor(red: UInt8(clamping: rgb[0]),
                         green: UInt8(clamping: rgb[1]),
                         blue: UInt8(clamping: rgb[2]))
    }

    private func setColor(_ color: TermColor, forKey key: String) {
        defaults.set([Int(color.red), Int(color.green), Int(color.blue)], forKey: key)
    }

    private enum Key {
        static let fontSize = "fontSize"
        static let background = "backgroundColor"
        static let foreground = "foregroundColor"
        static let shell = "shell"
        static let tabPlacement = "tabPlacement"
        static let newTabDirectory = "newTabDirectory"
        static let themeName = "themeName"
        static let scrollSpeed = "scrollSpeed"
        static let scrollbackLines = "scrollbackLines"
        static let claudeCommand = "claudeCommand"
        static let appIconName = "appIconName"
    }
}
