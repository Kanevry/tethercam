// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import XCTest
@testable import TetherCamCore

/// Minimal TCP listener that accepts connections and never speaks: the "app in
/// the foreground but wedged" case that must trip the HELLO timeout.
final class SilentListener {
    let port: UInt16
    private let fd: Int32
    private var clients: [Int32] = []
    private let lock = NSLock()
    private(set) var accepted = 0
    private var thread: Thread?

    init() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0, listen(sock, 8) == 0 else { throw TransportError.tcp("bind/listen failed") }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        fd = sock
        port = UInt16(bigEndian: bound.sin_port)
        let t = Thread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                lock.lock(); clients.append(c); accepted += 1; lock.unlock()
            }
        }
        thread = t
        t.start()
    }

    var acceptedCount: Int { lock.lock(); defer { lock.unlock() }; return accepted }

    func close() {
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        lock.lock(); clients.forEach { Darwin.close($0) }; clients.removeAll(); lock.unlock()
    }
}

final class ReceiverTests: XCTestCase {

    /// Bug caught: an off-by-one or missing cap in the ladder would either retry
    /// too eagerly against a phone that is not listening or grow without bound.
    func testBackoffLadderIs1To5SecondsCapped() {
        let ladder = (0..<7).map { ReceiverConfig.backoffMilliseconds(failures: $0) }
        XCTAssertEqual(ladder, [1000, 2000, 3000, 4000, 5000, 5000, 5000])
    }

    /// Bug caught: a receiver that connects to a silent peer and never times out
    /// stays in .starting forever. It must drop the socket and reconnect.
    func testHelloTimeoutReconnects() throws {
        let listener = try SilentListener()
        defer { listener.close() }

        var cfg = ReceiverConfig(endpoint: .tcp(host: "127.0.0.1", port: listener.port))
        cfg.helloTimeout = 0.3
        let receiver = Receiver(config: cfg)
        let states = Locked<[LinkState]>([])
        receiver.onState = { st in states.with { $0.append(st) } }
        receiver.start()
        defer { receiver.stop() }

        let deadline = Date().addingTimeInterval(4)
        while listener.acceptedCount < 2 && Date() < deadline { usleep(20_000) }
        XCTAssertGreaterThanOrEqual(listener.acceptedCount, 2, "no reconnect after HELLO timeout")
        XCTAssertTrue(states.value.contains(.starting))
        XCTAssertFalse(states.value.contains(.streaming))
    }

    /// Bug caught: stop() that does not join leaves the thread alive and the next
    /// test's listener sees a stray connection.
    func testStopJoinsThread() throws {
        let listener = try SilentListener()
        defer { listener.close() }
        let receiver = Receiver(config: ReceiverConfig(endpoint: .tcp(host: "127.0.0.1", port: listener.port)))
        receiver.start()
        usleep(100_000)
        let t0 = Date()
        receiver.stop()
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0, "stop() must not wait for the 5 s HELLO timeout")
        let before = listener.acceptedCount
        usleep(300_000)
        XCTAssertEqual(listener.acceptedCount, before, "thread still connecting after stop()")
    }
}

/// Tiny lock box for cross-thread assertions in tests.
final class Locked<T>: @unchecked Sendable {
    private var v: T
    private let lock = NSLock()
    init(_ v: T) { self.v = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
    func with(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
}
