import AppKit
import TeletypeCore

/// The bundled, user-selectable app icons (the Dock / running-app icon), in menu
/// order. Each `id` is the `.icns` resource's base name under `Resources/Icons`.
enum AppIconCatalog {
    static let all: [(id: String, label: String)] = [
        ("01-prompt", "Prompt"),
        ("03-fernschreiber", "Fernschreiber"),
        ("m1-spirit-prompt", "Spirit Prompt"),
        ("m3-crt-phosphor", "CRT Phosphor"),
        ("04-chicago-sterne", "Chicago Sterne"),
        ("m5-teletype-ember", "Teletype Ember"),
        ("m6-ember-prompt", "Ember Prompt"),
        ("m4-pixel-flamme", "Pixel Flamme"),
        ("m2-burning-marsh", "Burning Marsh"),
        ("02-lochstreifen", "Lochstreifen"),
        ("06-lochstreifen-prompt", "Lochstreifen Prompt"),
        ("05-illinois", "Illinois"),
        ("m7-map-terminal", "Map Terminal"),
    ]

    /// The icon used when none is chosen — a clean, universally readable prompt.
    static let defaultID = "01-prompt"

    static func image(id: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: id, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Sets the running app's Dock icon from the current setting (falling back to
    /// the default). The bundle's Finder icon stays whatever Info.plist points at.
    static func applyFromSettings() {
        let id = AppSettings.store.appIconName ?? defaultID
        NSApp.applicationIconImage = image(id: id) ?? image(id: defaultID)
    }
}
