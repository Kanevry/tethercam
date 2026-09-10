// SPDX-License-Identifier: MIT
// ClientInfoTests.swift
// CLIENT_INFO (PROTOCOL.md 4.11) and the setup-guide predicate.

import Darwin
import Foundation
import IucmProtocol
import XCTest
@testable import TetherCamCore

/// Listener that answers with HELLO and records every frame the receiver sends.
/// Enough to assert the outbound message ORDER; nothing after START is served.
final class HelloListener {
    let port: UInt16
    private let fd: Int32
    private let received = Locked<[IucmMessage]>([])
    private var thread: Thread?

    init(hello: HelloMessage) throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0, listen(sock, 8) == 0 else { throw TransportError.tcp("bind/listen failed") }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        fd = sock
        port = UInt16(bigEndian: bound.sin_port)
        let helloBytes = try IucmCodec.encode(.hello(hello))
        let t = Thread { [self] in
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            _ = helloBytes.withUnsafeBytes { Darwin.send(client, $0.baseAddress, helloBytes.count, 0) }
            var parser = IucmFrameParser()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = recv(client, &buf, buf.count, 0)
                if n <= 0 { break }
                if let msgs = try? parser.append(Data(buf[0..<n])), !msgs.isEmpty {
                    received.with { $0.append(contentsOf: msgs) }
                }
            }
            Darwin.close(client)
        }
        thread = t
        t.start()
    }

    var messages: [IucmMessage] { received.value }

    func close() {
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

final class ClientInfoTests: XCTestCase {

    /// Bug caught: the Mac app streams without ever identifying itself, so the
    /// phone can only say "a Mac is connected". CLIENT_INFO must go out AFTER
    /// HELLO and BEFORE START (PROTOCOL.md 4.11) — the order the phone relies on
    /// to name the receiver before the session begins.
    func testClientInfoIsSentAfterHelloAndBeforeStart() throws {
        let hello = HelloMessage(deviceName: "Test iPhone", appVersion: "1.2.3",
                                 cameras: [CameraInfo(id: 0, position: .back, name: "Back Camera")])
        let listener = try HelloListener(hello: hello)
        defer { listener.close() }

        var cfg = ReceiverConfig(endpoint: .tcp(host: "127.0.0.1", port: listener.port))
        cfg.clientVersion = "0.3.0 (7)"
        cfg.configTimeout = 30
        let receiver = Receiver(config: cfg)
        receiver.start()
        defer { receiver.stop() }

        let deadline = Date().addingTimeInterval(5)
        while listener.messages.count < 2 && Date() < deadline { usleep(20_000) }
        let types = listener.messages.map(\.type)
        XCTAssertGreaterThanOrEqual(types.count, 2, "receiver sent \(types)")
        XCTAssertEqual(Array(types.prefix(2)), [.clientInfo, .start],
                       "CLIENT_INFO must precede START, got \(types)")
        guard case .clientInfo(let info)? = listener.messages.first else {
            return XCTFail("first message is not CLIENT_INFO")
        }
        XCTAssertEqual(info.clientKind, .macApp)
        XCTAssertEqual(info.name, "TetherCam for Mac")
        XCTAssertEqual(info.version, "0.3.0 (7)")
    }
}

final class OnboardingPolicyTests: XCTestCase {

    /// Bug caught: the setup guide either never appears (the user is stranded on
    /// the approval step) or pops up on every launch of a working install. And a
    /// --headless run must never open a window.
    func testShouldShowPredicate() {
        // First launch, nothing approved yet.
        XCTAssertTrue(OnboardingPolicy.shouldShow(extensionEnabled: false, hasCompletedSetup: false, headless: false))
        // Dismissed once, but the extension is still not approved: show again.
        XCTAssertTrue(OnboardingPolicy.shouldShow(extensionEnabled: false, hasCompletedSetup: true, headless: false))
        // Approved but never confirmed: first-run guide.
        XCTAssertTrue(OnboardingPolicy.shouldShow(extensionEnabled: true, hasCompletedSetup: false, headless: false))
        // Working install, setup done: stay out of the way.
        XCTAssertFalse(OnboardingPolicy.shouldShow(extensionEnabled: true, hasCompletedSetup: true, headless: false))
        // Headless never opens a window, whatever the other flags say.
        for enabled in [true, false] {
            for done in [true, false] {
                XCTAssertFalse(OnboardingPolicy.shouldShow(extensionEnabled: enabled,
                                                           hasCompletedSetup: done, headless: true))
            }
        }
    }

    /// Bug (#25.1): while the extension was unapproved, `shouldShow` stayed true,
    /// so every extensionState report re-presented the window and "Done" could
    /// not suppress it. Automatic presentation now needs a real transition and
    /// yields to the in-launch suppress flag.
    func testAutomaticPresentationNeedsTransitionAndYieldsToDone() {
        func present(stateChanged: Bool, suppressed: Bool) -> Bool {
            OnboardingPolicy.shouldPresentAutomatically(extensionEnabled: false,
                                                        hasCompletedSetup: false,
                                                        headless: false,
                                                        stateChanged: stateChanged,
                                                        suppressedThisLaunch: suppressed)
        }
        // Unapproved extension, real transition: present.
        XCTAssertTrue(present(stateChanged: true, suppressed: false))
        // Same state re-reported by the installer poll: stay put.
        XCTAssertFalse(present(stateChanged: false, suppressed: false))
        // "Done" was pressed in this launch: no automatic presentation at all,
        // not even on a further transition.
        XCTAssertFalse(present(stateChanged: true, suppressed: true))
        XCTAssertFalse(present(stateChanged: false, suppressed: true))
        // Headless still never opens a window, transition or not.
        XCTAssertFalse(OnboardingPolicy.shouldPresentAutomatically(extensionEnabled: false,
                                                                   hasCompletedSetup: false,
                                                                   headless: true,
                                                                   stateChanged: true,
                                                                   suppressedThisLaunch: false))
        // Healthy install that has been confirmed: nothing to show on a change.
        XCTAssertFalse(OnboardingPolicy.shouldPresentAutomatically(extensionEnabled: true,
                                                                   hasCompletedSetup: true,
                                                                   headless: false,
                                                                   stateChanged: true,
                                                                   suppressedThisLaunch: false))
    }
}
