// SPDX-License-Identifier: MIT
import XCTest
@testable import TetherCamCore

final class ContractTests: XCTestCase {
    func testPublishedFormatIs1080p30() {
        XCTAssertEqual(TetherCamContract.width, 1920)
        XCTAssertEqual(TetherCamContract.height, 1080)
        XCTAssertEqual(TetherCamContract.fps, 30)
    }
}
