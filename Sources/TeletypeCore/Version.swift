import Foundation

/// A released version, as far as "is there something newer?" needs it.
/// Deliberately not a full semver implementation: a pre-release suffix is
/// dropped rather than ordered, because we are reporting availability, not
/// resolving dependencies.
public struct Version: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        // Tags are usually "v1.99.1"; a "-beta.1" suffix is cut off.
        var trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        if let dash = trimmed.firstIndex(of: "-") { trimmed = String(trimmed[..<dash]) }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, let first = Int(parts[0]) else { return nil }
        major = first
        minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// What the app shows about one dependency.
public struct UpdateStatus: Equatable, Sendable {
    public let current: Version
    public let latest: Version

    public init(current: Version, latest: Version) {
        self.current = current
        self.latest = latest
    }

    public var hasUpdate: Bool { current < latest }

    /// A new major version — worth knowing before pulling it in, because the
    /// API it offers may well have changed.
    public var isMajorStep: Bool { hasUpdate && latest.major > current.major }

    public var summary: String {
        hasUpdate ? "\(current) → \(latest)" : "\(current) (up to date)"
    }
}
