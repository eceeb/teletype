import AppKit
import CoreText

/// The terminal's font: the bundled JetBrainsMono Nerd Font Mono (so Nerd-Font
/// prompt icons render), falling back to the system monospaced font if loading
/// fails. Loaded once, on the main actor.
@MainActor
enum TerminalFont {
    static let size: CGFloat = 13

    static let regular: NSFont = load("JetBrainsMonoNerdFontMono-Regular")
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    static let bold: NSFont = load("JetBrainsMonoNerdFontMono-Bold")
        ?? .monospacedSystemFont(ofSize: size, weight: .bold)

    /// Registers a bundled .ttf and builds an NSFont straight from its
    /// descriptor (no font-name guessing).
    private static func load(_ resource: String) -> NSFont? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        return NSFont(descriptor: descriptor, size: size)
    }
}
