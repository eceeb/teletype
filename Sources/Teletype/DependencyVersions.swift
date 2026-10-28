import Foundation
import TeletypeCore

/// The libraries this build was compiled against, read from the Info.plist that
/// `packaging/install.sh` fills from Package.resolved.
///
/// A plain `swift build` binary has no Info.plist, so there is nothing to check
/// there — which is correct: a dev build is rebuilt from the current checkout
/// anyway.
enum DependencyVersions {
    /// Repositories we know how to ask about, by the identity SwiftPM uses.
    private static let repositories = [
        "swiftterm": ("SwiftTerm", "migueldeicaza/SwiftTerm"),
        "swift-argument-parser": ("swift-argument-parser", "apple/swift-argument-parser")
    ]

    static func builtAgainst() -> [Dependency] {
        guard let stored = Bundle.main.object(forInfoDictionaryKey: "TeletypeDependencyVersions")
                as? [String: String] else { return [] }
        return stored.compactMap { identity, text in
            guard let (name, repository) = repositories[identity],
                  let version = Version(text) else { return nil }
            return Dependency(name: name, repository: repository, current: version)
        }
        .sorted { $0.name < $1.name }
    }
}
