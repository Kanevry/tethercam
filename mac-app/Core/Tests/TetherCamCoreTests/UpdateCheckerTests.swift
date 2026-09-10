// SPDX-License-Identifier: MIT
// UpdateCheckerTests.swift
// The daily update hint: version compare, rate limit, failure handling.
// Fully offline — fetch, store and clock are injected.

import Foundation
import XCTest
@testable import TetherCamCore

/// In-memory `KeyValueStore`; never touches the real defaults domain.
private final class MemoryStore: KeyValueStore {
    private var strings: [String: String] = [:]
    private var doubles: [String: Double] = [:]

    func stringValue(forKey key: String) -> String? { strings[key] }
    func setString(_ value: String?, forKey key: String) { strings[key] = value }
    func doubleValue(forKey key: String) -> Double? { doubles[key] }
    func setDouble(_ value: Double, forKey key: String) { doubles[key] = value }
}

private enum FakeError: Error { case offline }

final class UpdateCheckerTests: XCTestCase {

    private func payload(tag: String, url: String = "https://github.com/Kanevry/tethercam/releases/tag/v9.9.9") -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)"}"#.utf8)
    }

    private func makeChecker(current: String,
                             store: MemoryStore = MemoryStore(),
                             now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000_000) },
                             calls: (() -> Void)? = nil,
                             fetch: @escaping (URL) async throws -> Data) -> UpdateChecker {
        UpdateChecker(currentVersion: current,
                      fetch: { url in
                          calls?()
                          return try await fetch(url)
                      },
                      store: store,
                      now: now,
                      minimumInterval: 86_400)
    }

    func testNewerReleaseIsAvailable() async {
        let checker = makeChecker(current: "0.3.0") { _ in
            self.payload(tag: "v0.4.0", url: "https://github.com/Kanevry/tethercam/releases/tag/v0.4.0")
        }
        let result = await checker.check(force: true)
        XCTAssertEqual(result, .available(latest: "v0.4.0",
                                          url: URL(string: "https://github.com/Kanevry/tethercam/releases/tag/v0.4.0")!))
    }

    func testSameVersionIsUpToDate() async {
        let checker = makeChecker(current: "0.3.0") { _ in self.payload(tag: "v0.3.0") }
        let result = await checker.check(force: true)
        XCTAssertEqual(result, .upToDate(latest: "v0.3.0"))
    }

    func testOlderRemoteIsUpToDate() async {
        // Dev build ahead of the newest release — never offer a downgrade.
        let checker = makeChecker(current: "0.4.0") { _ in self.payload(tag: "v0.3.0") }
        let result = await checker.check(force: true)
        XCTAssertEqual(result, .upToDate(latest: "v0.3.0"))
    }

    func testNetworkErrorFailsAndDoesNotConsumeTheInterval() async {
        let store = MemoryStore()
        var networkCalls = 0
        let checker = makeChecker(current: "0.3.0",
                                  store: store,
                                  calls: { networkCalls += 1 }) { _ in throw FakeError.offline }

        let first = await checker.check(force: false)
        guard case .failed = first else { return XCTFail("expected .failed, got \(first)") }
        XCTAssertNil(store.doubleValue(forKey: UpdateChecker.lastRunKey),
                     "a failed check must not consume the daily interval")

        // A retry right away still hits the network instead of being rate limited.
        let second = await checker.check(force: false)
        guard case .failed = second else { return XCTFail("expected .failed, got \(second)") }
        XCTAssertEqual(networkCalls, 2)
    }

    func testMalformedTagFails() async {
        let checker = makeChecker(current: "0.3.0") { _ in self.payload(tag: "nightly-build") }
        let result = await checker.check(force: true)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
    }

    func testMalformedResponseFails() async {
        let checker = makeChecker(current: "0.3.0") { _ in Data("not json".utf8) }
        let result = await checker.check(force: true)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
    }

    func testSecondCallInsideTheIntervalIsRateLimited() async {
        let store = MemoryStore()
        var networkCalls = 0
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let checker = makeChecker(current: "0.3.0",
                                  store: store,
                                  now: { clock },
                                  calls: { networkCalls += 1 }) { _ in self.payload(tag: "v0.3.0") }

        let first = await checker.check(force: false)
        XCTAssertEqual(first, .upToDate(latest: "v0.3.0"))
        XCTAssertEqual(networkCalls, 1)

        clock = Date(timeIntervalSince1970: 1_000_000 + 3_600)
        let second = await checker.check(force: false)
        XCTAssertEqual(second, .skippedRateLimited)
        let due = await checker.checkIfDue()
        XCTAssertNil(due, "checkIfDue reports nothing while rate limited")
        XCTAssertEqual(networkCalls, 1, "no request inside the interval")

        // force bypasses the interval.
        let forced = await checker.check(force: true)
        XCTAssertEqual(forced, .upToDate(latest: "v0.3.0"))
        XCTAssertEqual(networkCalls, 2)

        // Once a full day has passed the check runs by itself again.
        clock = Date(timeIntervalSince1970: 1_000_000 + 3_600 + 86_400)
        let nextDay = await checker.checkIfDue()
        XCTAssertEqual(nextDay, .upToDate(latest: "v0.3.0"))
        XCTAssertEqual(networkCalls, 3)
    }

    func testLastKnownLatestIsRememberedForTheMenu() async {
        let store = MemoryStore()
        let checker = makeChecker(current: "0.3.0", store: store) { _ in self.payload(tag: "v0.5.0") }
        _ = await checker.check(force: true)
        XCTAssertEqual(store.stringValue(forKey: UpdateChecker.latestSeenKey), "v0.5.0")
        XCTAssertEqual(checker.lastKnownLatest, "v0.5.0")
    }

    // Bug guarded: the rate-limit stamp written before the tag is validated. A
    // release named "nightly" would then burn the daily budget on every launch
    // and the user would never see a real update for 24 h.
    func testUnreadableTagWritesNeitherStampNorLastSeen() async {
        let store = MemoryStore()
        let checker = makeChecker(current: "0.3.0", store: store) { _ in self.payload(tag: "nightly-build") }
        let result = await checker.check(force: false)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertNil(store.doubleValue(forKey: UpdateChecker.lastRunKey))
        XCTAssertNil(store.stringValue(forKey: UpdateChecker.latestSeenKey))
        XCTAssertNil(checker.lastKnownLatest)
    }

    // Bug guarded: a prerelease tag treated as a numeric version (e.g. by
    // parsing the leading digits of "0-rc1"), so the menu would offer an
    // unreleased build as an update.
    func testPrereleaseTagIsNotOfferedAsAnUpdate() async {
        let checker = makeChecker(current: "0.3.0") { _ in self.payload(tag: "v0.4.0-rc1") }
        let result = await checker.check(force: true)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertNil(Version("0.4.0-rc1"))
    }

    // Bug guarded: GitHub answers a rate-limited request with HTTP 403 and a
    // JSON body that has neither tag_name nor html_url. The checker ignores the
    // status code, so that body must fail decoding instead of being mistaken
    // for a release — and it must not consume the daily interval.
    func testRateLimitBodyWithoutReleaseFieldsFails() async {
        let store = MemoryStore()
        let body = Data(#"{"message":"API rate limit exceeded for 1.2.3.4","documentation_url":"https://docs.github.com/rest"}"#.utf8)
        let checker = makeChecker(current: "0.3.0", store: store) { _ in body }
        let result = await checker.check(force: true)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertNil(store.doubleValue(forKey: UpdateChecker.lastRunKey))
    }

    // Bug guarded (#w3): the release URL comes from the network and is handed
    // to NSWorkspace.open. Only an https page on github.com may pass; anything
    // else is a failure, never a silent "up to date".
    func testHTTPSGitHubReleaseURLIsAccepted() async {
        let checker = makeChecker(current: "0.3.0") { _ in
            self.payload(tag: "v0.4.0", url: "https://github.com/Kanevry/tethercam/releases/tag/v0.4.0")
        }
        let result = await checker.check(force: true)
        XCTAssertEqual(result, .available(latest: "v0.4.0",
                                          url: URL(string: "https://github.com/Kanevry/tethercam/releases/tag/v0.4.0")!))
    }

    func testFileURLIsRejected() async {
        let store = MemoryStore()
        let checker = makeChecker(current: "0.3.0", store: store) { _ in
            self.payload(tag: "v0.4.0", url: "file:///Applications/Malware.app")
        }
        let result = await checker.check(force: true)
        XCTAssertEqual(result, .failed("release URL rejected"))
        XCTAssertNil(store.doubleValue(forKey: UpdateChecker.lastRunKey))
    }

    func testForeignHostIsRejected() async {
        let checker = makeChecker(current: "0.3.0") { _ in
            self.payload(tag: "v0.4.0", url: "https://evil.example/Kanevry/tethercam/releases/tag/v0.4.0")
        }
        let result = await checker.check(force: true)
        XCTAssertEqual(result, .failed("release URL rejected"))
    }

    // A newer release whose html_url is unusable must not read as "up to date":
    // that would hide the update on every future launch.
    func testNewerReleaseWithEmptyURLFailsAndKeepsTheInterval() async {
        let store = MemoryStore()
        let checker = makeChecker(current: "0.3.0", store: store) { _ in
            self.payload(tag: "v0.4.0", url: "")
        }
        let result = await checker.check(force: false)
        XCTAssertEqual(result, .failed("release URL rejected"))
        XCTAssertNil(store.doubleValue(forKey: UpdateChecker.lastRunKey),
                     "a rejected release URL must not consume the daily interval")
        XCTAssertNil(store.stringValue(forKey: UpdateChecker.latestSeenKey))
    }

    func testReleaseURLGate() {
        XCTAssertTrue(UpdateChecker.isAcceptableReleaseURL(URL(string: "https://github.com/Kanevry/tethercam")!))
        XCTAssertTrue(UpdateChecker.isAcceptableReleaseURL(URL(string: "HTTPS://GitHub.com/Kanevry")!))
        XCTAssertFalse(UpdateChecker.isAcceptableReleaseURL(URL(string: "http://github.com/Kanevry")!))
        XCTAssertFalse(UpdateChecker.isAcceptableReleaseURL(URL(string: "file:///Applications/X.app")!))
        XCTAssertFalse(UpdateChecker.isAcceptableReleaseURL(URL(string: "https://evil.example/x")!))
        XCTAssertFalse(UpdateChecker.isAcceptableReleaseURL(URL(string: "https://github.com.evil.example/x")!))
    }

    func testVersionParsingWithAndWithoutPrefix() {
        XCTAssertEqual(Version("v0.3.0"), Version("0.3.0"))
        XCTAssertEqual(Version("1.2"), Version("1.2.0"))
        XCTAssertEqual(Version("2"), Version("2.0.0"))
        XCTAssertTrue(Version("v0.3.1")! > Version("0.3.0")!)
        XCTAssertTrue(Version("v0.10.0")! > Version("v0.9.9")!)
        XCTAssertNil(Version("nightly"))
        XCTAssertNil(Version("v1.2.x"))
        XCTAssertNil(Version("1.2.3.4"))
        XCTAssertNil(Version(""))
        XCTAssertNil(Version("v"))
    }
}

extension Version: Equatable {
    static func == (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
    }
}
