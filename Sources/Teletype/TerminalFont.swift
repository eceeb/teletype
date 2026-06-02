import AppKit
import CoreText

/// The terminal's font: the bundled JetBrainsMono Nerd Font Mono (so Nerd-Font
/// prompt icons render), produced at any size, falling back to the system
/// monospaced font if loading fails. Descriptors are loaded once, on the main actor.
@MainActor
enum TerminalFont {
    private static let regularDescriptor = loadDescriptor("JetBrainsMonoNerdFontMono-Regular")
    private static let boldDescriptor = loadDescriptor("JetBrainsMonoNerdFontMono-Bold")

    static func regular(ofSize size: CGFloat) -> NSFont {
        font(regularDescriptor, size: size, fallbackWeight: .regular)
    }

    static func bold(ofSize size: CGFloat) -> NSFont {
        font(boldDescriptor, size: size, fallbackWeight: .bold)
    }

    private static func font(_ descriptor: NSFontDescriptor?, size: CGFloat, fallbackWeight: NSFont.Weight) -> NSFont {
        if let descriptor, let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: fallbackWeight)
    }

    /// Registers a bundled .ttf and returns its font descriptor (no name guessing).
    private static func loadDescriptor(_ resource: String) -> NSFontDescriptor? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor])?.first
    }
}
