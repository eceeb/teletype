import AppKit
import TeletypeCore

/// The shared settings store and a notification for live updates.
enum AppSettings {
    static let store = TerminalSettings()
    static let didChange = Notification.Name("teletype.settingsDidChange")

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

extension NSColor {
    convenience init(_ color: TermColor) {
        self.init(srgbRed: CGFloat(color.red) / 255,
                  green: CGFloat(color.green) / 255,
                  blue: CGFloat(color.blue) / 255,
                  alpha: 1)
    }
}

extension TermColor {
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        self.init(red: UInt8(clamping: Int((rgb.redComponent * 255).rounded())),
                  green: UInt8(clamping: Int((rgb.greenComponent * 255).rounded())),
                  blue: UInt8(clamping: Int((rgb.blueComponent * 255).rounded())))
    }
}
