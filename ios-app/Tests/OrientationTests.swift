import XCTest
@testable import UsbCam

/// Gravity vectors for the four physical poses, in CoreMotion device space
/// (+x right along the short edge, +y towards the front camera, +z out of the
/// screen). Gravity points down in world space.
private enum Pose {
    static let portrait: (CGFloat, CGFloat) = (0, -1)          // upright
    static let portMuchRight: (CGFloat, CGFloat) = (-1, 0)     // landscape, charge port right
    static let portMuchLeft: (CGFloat, CGFloat) = (1, 0)       // landscape, charge port left
    static let upsideDown: (CGFloat, CGFloat) = (0, 1)
}

final class OrientationTests: XCTestCase {

    // MARK: continuous angle — the axis convention itself

    func testContinuousAnglePerPose() {
        XCTAssertEqual(OrientationMath.continuousAngle(gx: Pose.portrait.0, gy: Pose.portrait.1), 90, accuracy: 0.001)
        XCTAssertEqual(OrientationMath.continuousAngle(gx: Pose.portMuchRight.0, gy: Pose.portMuchRight.1), 0, accuracy: 0.001)
        XCTAssertEqual(OrientationMath.continuousAngle(gx: Pose.portMuchLeft.0, gy: Pose.portMuchLeft.1), 180, accuracy: 0.001)
        XCTAssertEqual(OrientationMath.continuousAngle(gx: Pose.upsideDown.0, gy: Pose.upsideDown.1), 270, accuracy: 0.001)
    }

    func testContinuousAngleIsAlwaysInRange() {
        for deg in stride(from: 0.0, to: 360.0, by: 7.0) {
            let r = deg * .pi / 180
            let a = OrientationMath.continuousAngle(gx: CGFloat(cos(r)), gy: CGFloat(sin(r)))
            XCTAssertGreaterThanOrEqual(a, 0)
            XCTAssertLessThan(a, 360)
        }
    }

    /// The magnitude is scale-invariant in angle: a steeply tilted phone still
    /// reports the correct sector, only with a smaller m. This is the whole
    /// point of the sensor over the horizon-level coordinator.
    func testSteepTiltStillResolvesSector() {
        // portrait pose, but the phone points 80 degrees down: in-plane part is small
        let gx: CGFloat = 0.0, gy: CGFloat = -0.17
        XCTAssertGreaterThan(OrientationMath.magnitude(gx: gx, gy: gy), OrientationMath.flatThreshold)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: gx, gy: gy, last: 0), 90)
    }

    // MARK: quantisation — all four sectors from a neutral start

    func testQuantizeAllFourSectors() {
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: Pose.portrait.0, gy: Pose.portrait.1, last: 270), 90)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: Pose.portMuchRight.0, gy: Pose.portMuchRight.1, last: 180), 0)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: Pose.portMuchLeft.0, gy: Pose.portMuchLeft.1, last: 0), 180)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: Pose.upsideDown.0, gy: Pose.upsideDown.1, last: 90), 270)
    }

    func testQuantizeKeepsSectorItIsAlreadyIn() {
        // 10 degrees off portrait: same sector, no change
        let a = angleVector(100)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: a.0, gy: a.1, last: 90), 90)
    }

    // MARK: hysteresis (margin 5 since 2026-09-05, was 15)

    func testSectorIsTheNearestMultipleOf90() {
        // The pinned pair from the tripod bug report: with a 15-degree margin the
        // sector stayed put and the leveller had to cover 55+ degrees.
        let c30 = angleVector(30)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: c30.0, gy: c30.1, last: 0), 0)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: c30.0, gy: c30.1, last: 90), 0)
        XCTAssertEqual(LevelerMath.residualAngle(continuous: 30, sector: 0), 30, accuracy: 0.001)

        let c70 = angleVector(70)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: c70.0, gy: c70.1, last: 90), 90)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: c70.0, gy: c70.1, last: 0), 90)
        XCTAssertEqual(LevelerMath.residualAngle(continuous: 70, sector: 90), -20, accuracy: 0.001)
    }

    func testBoundaryInsideMarginDoesNotSwitch() {
        // 41 degrees continuous: distance to 90 is 49 <= 45+5, still holds
        let v = angleVector(41)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: v.0, gy: v.1, last: 90), 90)
    }

    func testBoundaryJustInsideMarginDoesNotSwitch() {
        // exactly 50 degrees from 90 -> distance 40 <= 45+5, holds
        let v = angleVector(50)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: v.0, gy: v.1, last: 90), 90)
    }

    func testBoundaryBeyondMarginSwitches() {
        // 39 degrees continuous: distance to 90 is 51 > 50 -> switch to nearest (0)
        let v = angleVector(39)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: v.0, gy: v.1, last: 90), 0)
    }

    func testHysteresisBandIsFortyToFiftyDegrees() {
        // The band the boundary can sit in: coming from 0 the sector holds up to
        // 50, coming from 90 it holds down to 40 — a 10-degree overlap, 2x margin.
        let hold = angleVector(50)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: hold.0, gy: hold.1, last: 0), 0)
        let flip = angleVector(51)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: flip.0, gy: flip.1, last: 0), 90)
        let holdDown = angleVector(40)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: holdDown.0, gy: holdDown.1, last: 90), 90)
    }

    func testHysteresisIsSymmetricAcrossTheWrap() {
        // last = 0, continuous 311 -> distance 49, holds; 309 -> distance 51, switches
        let hold = angleVector(311)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: hold.0, gy: hold.1, last: 0), 0)
        let flip = angleVector(309)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: flip.0, gy: flip.1, last: 0), 270)
    }

    /// The whole reason the margin came down: the residual the leveller is asked
    /// to absorb must stay inside the clamp for any steady pose.
    func testResidualNeverExceedsFiftyForAnyPoseAndAnyPreviousSector() {
        for deg in stride(from: 0.0, to: 360.0, by: 0.5) {
            let v = angleVector(CGFloat(deg))
            for last in [CGFloat(0), 90, 180, 270] {
                let sector = OrientationMath.quantizeAngle(gx: v.0, gy: v.1, last: last)
                let residual = LevelerMath.residualAngle(continuous: CGFloat(deg), sector: sector)
                XCTAssertLessThanOrEqual(abs(residual), 50 + 1e-6,
                                         "cont \(deg) last \(last) -> sector \(sector)")
                XCTAssertLessThanOrEqual(abs(LevelerMath.clampResidual(residual)),
                                         LevelerMath.maxResidualDeg + 1e-6)
            }
        }
    }

    // MARK: flat fallback

    func testFlatKeepsLastAngle() {
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: 0.05, gy: 0.05, last: 180), 180)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: 0, gy: 0, last: 270), 270)
    }

    func testJustAboveFlatThresholdIsTrusted() {
        // m = 0.13 pointing at continuous 0 (charge port right)
        XCTAssertEqual(OrientationMath.quantizeAngle(gx: -0.13, gy: 0, last: 180), 0)
    }

    // MARK: sensor dwell time

    func testSensorAdoptsFirstFixImmediately() {
        let s = OrientationSensor()
        s.ingest(SIMD3(-1, 0, 0), at: 0)
        XCTAssertTrue(s.hasFix)
        XCTAssertEqual(s.captureAngle, 0)
    }

    func testSensorRequiresDwellBeforeSwitching() {
        let s = OrientationSensor()
        s.ingest(SIMD3(-1, 0, 0), at: 0)          // landscape, port right -> 0
        s.ingest(SIMD3(0, -1, 0), at: 0.1)        // portrait candidate
        XCTAssertEqual(s.captureAngle, 0, "switch must not happen before the dwell time")
        s.ingest(SIMD3(0, -1, 0), at: 0.3)
        XCTAssertEqual(s.captureAngle, 0, "0.2 s is still below the 0.3 s dwell")
        s.ingest(SIMD3(0, -1, 0), at: 0.45)
        XCTAssertEqual(s.captureAngle, 90)
    }

    func testSensorDropsPendingSwitchWhenPoseReturns() {
        let s = OrientationSensor()
        s.ingest(SIMD3(-1, 0, 0), at: 0)
        s.ingest(SIMD3(0, -1, 0), at: 0.1)        // pending 90
        s.ingest(SIMD3(-1, 0, 0), at: 0.2)        // back to 0, pending cleared
        s.ingest(SIMD3(0, -1, 0), at: 0.3)        // pending restarts here
        s.ingest(SIMD3(0, -1, 0), at: 0.5)        // only 0.2 s elapsed
        XCTAssertEqual(s.captureAngle, 0)
    }

    func testSensorHoldsAngleWhenFlat() {
        let s = OrientationSensor()
        s.ingest(SIMD3(-1, 0, 0), at: 0)
        s.ingest(SIMD3(0, 0, -1), at: 1)          // camera straight down
        XCTAssertEqual(s.captureAngle, 0)
        XCTAssertLessThan(s.confidence, OrientationMath.flatThreshold)
    }

    /// Unit vector for a given *continuous* angle, inverting `continuousAngle`.
    private func angleVector(_ continuous: CGFloat) -> (CGFloat, CGFloat) {
        let deg = 270 - continuous
        let r = Double(deg) * .pi / 180
        return (CGFloat(sin(r)), CGFloat(cos(r)))
    }
}
