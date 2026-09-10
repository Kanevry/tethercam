// SPDX-License-Identifier: MIT
// UpdateChecker.swift
// TetherCam for macOS: asks the GitHub releases API once a day whether a newer
// version exists. Pure logic plus injected fetch/store/clock, so it is testable
// offline and carries no AppKit, no timer and no UI.

import Foundation

/// What a single update check produced.
///
/// `.failed` is deliberately its own case instead of a thrown error: the caller
/// is a menu item, and "could not check" is a state it has to render, not an
/// exception it has to catch.
public enum UpdateResult: Equatable, Sendable {
    /// The running build is the newest published release (or newer — dev builds).
    case upToDate(latest: String)
    /// A newer release exists; `url` is its release page.
    case available(latest: String, url: URL)
    /// Network, decoding or version-parsing problem. The message is for the log.
    case failed(String)
    /// The last check is younger than `minimumInterval` and `force` was false.
    case skippedRateLimited
}

/// The slice of `UserDefaults` the checker needs.
///
/// Injected so tests never touch the real defaults domain.
public protocol KeyValueStore: AnyObject {
    func stringValue(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
    /// `nil` when the key was never written.
    func doubleValue(forKey key: String) -> Double?
    func setDouble(_ value: Double, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    public func stringValue(forKey key: String) -> String? { string(forKey: key) }
    public func setString(_ value: String?, forKey key: String) { set(value, forKey: key) }
    public func doubleValue(forKey key: String) -> Double? {
        object(forKey: key) == nil ? nil : double(forKey: key)
    }
    public func setDouble(_ value: Double, forKey key: String) { set(value, forKey: key) }
}

/// Checks GitHub for a newer TetherCam release.
///
/// Why at most once per day: users outside Homebrew get no update signal at all,
/// and a camera extension only takes effect with a higher `CFBundleVersion`, so a
/// hint matters — but the app is a menu-bar process that may run for days, and
/// the unauthenticated GitHub API allows 60 requests/hour per IP. One request per
/// launch-day is enough for a hint and cannot exhaust that budget.
///
/// Why no Sparkle: a real updater framework (delta packages, signing keys, an
/// appcast to host) is deferred — see
/// `docs/superpowers/specs/2026-09-10-mac-app-1.0.md`. This class only *tells*
/// the user; downloading and installing stays manual (.dmg / Homebrew cask).
public final class UpdateChecker {

    /// UNIX time of the last *successful* check. A failed check is not recorded,
    /// so the next launch may retry immediately.
    public static let lastRunKey = "updateCheck.lastRun"
    /// The newest release tag seen by a successful check, so the menu can show a
    /// hint without issuing a new request.
    public static let latestSeenKey = "updateCheck.latestSeen"

    /// The releases endpoint. GitHub already excludes drafts and prereleases here.
    public static let releasesURL = URL(string: "https://api.github.com/repos/Kanevry/tethercam/releases/latest")!

    private let currentVersion: String
    private let fetch: (URL) async throws -> Data
    private let store: KeyValueStore
    private let now: () -> Date
    private let minimumInterval: TimeInterval

    /// - Parameters:
    ///   - currentVersion: `CFBundleShortVersionString`, with or without a "v".
    ///   - fetch: performs the GET. Defaults to `URLSession.shared` with the
    ///     GitHub `Accept` header and a TetherCam User-Agent.
    ///   - store: where the rate-limit stamp and the last seen tag live.
    ///   - now: clock, injectable for tests.
    ///   - minimumInterval: minimum distance between two network calls (24 h).
    public init(currentVersion: String,
                fetch: ((URL) async throws -> Data)? = nil,
                store: KeyValueStore = UserDefaults.standard,
                now: @escaping () -> Date = Date.init,
                minimumInterval: TimeInterval = 86_400) {
        self.currentVersion = currentVersion
        self.store = store
        self.now = now
        self.minimumInterval = minimumInterval
        self.fetch = fetch ?? UpdateChecker.makeDefaultFetch(currentVersion: currentVersion)
    }

    /// The tag of the newest release a previous successful check saw, if any.
    /// Lets the menu render a hint at launch without a request.
    public var lastKnownLatest: String? { store.stringValue(forKey: Self.latestSeenKey) }

    /// Runs a check only when the interval has elapsed.
    /// - Returns: `nil` when the last check is still fresh, otherwise the result.
    public func checkIfDue() async -> UpdateResult? {
        let result = await check(force: false)
        if case .skippedRateLimited = result { return nil }
        return result
    }

    /// Runs a check. `force: true` bypasses the interval (menu item "Check now").
    public func check(force: Bool) async -> UpdateResult {
        if !force, !isDue() { return .skippedRateLimited }

        let data: Data
        do {
            data = try await fetch(Self.releasesURL)
        } catch {
            // Not recorded as a run: a failed check may retry on the next launch.
            return .failed("request failed: \(error.localizedDescription)")
        }

        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            return .failed("malformed response: \(error.localizedDescription)")
        }

        guard let remote = Version(release.tag_name) else {
            // A tag we cannot read is never an update — silence beats a false alarm.
            return .failed("unreadable tag: \(release.tag_name)")
        }
        guard let mine = Version(currentVersion) else {
            return .failed("unreadable local version: \(currentVersion)")
        }

        guard remote > mine else {
            // Also the dev-build case: a local version ahead of the release is fine.
            store.setDouble(now().timeIntervalSince1970, forKey: Self.lastRunKey)
            store.setString(release.tag_name, forKey: Self.latestSeenKey)
            return .upToDate(latest: release.tag_name)
        }
        // A newer release with a URL we refuse to open is a failure, not "up to
        // date": silently reporting the newest build as current would hide the
        // update forever. The stamp stays unwritten so the next launch retries.
        guard let url = URL(string: release.html_url), Self.isAcceptableReleaseURL(url) else {
            return .failed("release URL rejected")
        }
        store.setDouble(now().timeIntervalSince1970, forKey: Self.lastRunKey)
        store.setString(release.tag_name, forKey: Self.latestSeenKey)
        return .available(latest: release.tag_name, url: url)
    }

    /// Gate for the one URL this app hands to `NSWorkspace.open`. The payload
    /// comes from the network, so anything but an https page on github.com is
    /// refused — `file:///Applications/…` or a foreign host would turn a JSON
    /// field into "the app launches what the response says".
    static func isAcceptableReleaseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com"
    }

    private func isDue() -> Bool {
        guard let last = store.doubleValue(forKey: Self.lastRunKey) else { return true }
        return now().timeIntervalSince1970 - last >= minimumInterval
    }

    private static func makeDefaultFetch(currentVersion: String) -> (URL) async throws -> Data {
        { url in
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TetherCam/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }
    }

    /// The two fields of the releases payload we use.
    private struct Release: Decodable {
        let tag_name: String  // swiftlint:disable:this identifier_name
        let html_url: String  // swiftlint:disable:this identifier_name
    }
}

/// Numeric `major.minor.patch`, tolerant of a leading "v", nothing else.
struct Version: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        major = numbers[0]
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
