import Foundation

/// One library the app is built against.
public struct Dependency: Equatable, Sendable {
    public let name: String
    /// "owner/repo" on GitHub.
    public let repository: String
    public let current: Version

    public init(name: String, repository: String, current: Version) {
        self.name = name
        self.repository = repository
        self.current = current
    }
}

/// The outcome for one dependency. `status` is nil when we could not find out —
/// offline, rate-limited, or a tag we cannot read. That is deliberately *not*
/// the same as "up to date", which would quietly hide updates.
public struct DependencyUpdate: Sendable {
    public let dependency: Dependency
    public let status: UpdateStatus?
    public let failed: Bool

    public init(dependency: Dependency, status: UpdateStatus?, failed: Bool) {
        self.dependency = dependency
        self.status = status
        self.failed = failed
    }
}

/// Asks GitHub for the newest release of each dependency.
///
/// The fetch is injected so the logic can be tested without a network, and so
/// the caller decides what a request looks like.
public struct UpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let fetch: Fetch

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func check(_ dependencies: [Dependency]) async -> [DependencyUpdate] {
        var results: [DependencyUpdate] = []
        for dependency in dependencies {
            results.append(await check(dependency))
        }
        return results
    }

    private func check(_ dependency: Dependency) async -> DependencyUpdate {
        guard let url = URL(string:
            "https://api.github.com/repos/\(dependency.repository)/releases/latest") else {
            return DependencyUpdate(dependency: dependency, status: nil, failed: true)
        }
        do {
            let data = try await fetch(url)
            guard let tag = try? JSONDecoder().decode(Release.self, from: data).tag_name,
                  let latest = Version(tag) else {
                return DependencyUpdate(dependency: dependency, status: nil, failed: false)
            }
            return DependencyUpdate(
                dependency: dependency,
                status: UpdateStatus(current: dependency.current, latest: latest),
                failed: false)
        } catch {
            return DependencyUpdate(dependency: dependency, status: nil, failed: true)
        }
    }

    private struct Release: Decodable {
        let tag_name: String
    }

    /// Whether enough time has passed. A stored date in the future — a clock
    /// change, a restored backup — must not lock the check out forever.
    public static func shouldCheck(lastCheck: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}

/// The short, two-line form the sidebar shows when something is out of date.
public enum UpdateNotice {
    public struct Text: Equatable, Sendable {
        public let title: String
        public let detail: String
    }

    public static func text(for updates: [DependencyUpdate]) -> Text? {
        guard !updates.isEmpty else { return nil }
        let major = updates.contains { $0.status?.isMajorStep == true }
        let detail = major ? "New major version" : "Update available"

        if updates.count == 1, let only = updates.first, let status = only.status {
            return Text(title: "\(only.dependency.name) \(status.latest)", detail: detail)
        }
        return Text(title: "\(updates.count) library updates", detail: detail)
    }
}
