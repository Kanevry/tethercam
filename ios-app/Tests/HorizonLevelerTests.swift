import CoreMedia
import CoreVideo
import XCTest
@testable import TetherCam

final class HorizonLevelerTests: XCTestCase {

    // MARK: - residualAngle

    /// The connection applied the sector, the residual is what is left. Sign is
    /// the videoRotationAngle convention: positive means the picture still has to
    /// be turned clockwise.
    func testResidualIsContinuousMinusSector() {
        XCTAssertEqual(LevelerMath.residualAngle(continuous: 8, sector: 0), 8, accuracy: 1e-9)
        XCTAssertEqual(LevelerMath.residualAngle(continuous: 98, sector: 90), 8, accuracy: 1e-9)
        XCTAssertEqual(LevelerMath.residualAngle(continuous: 82, sector: 90), -8, accuracy: 1e-9)
    }

    /// A phone rolled 10 degrees counter-clockwise out of the landscape pose
    /// reports gravity (-cos 10, sin 10) and therefore a continuous angle of 350.
    /// Against sector 0 that must read as -10, not +350.
    func testResidualWrapsAcrossZero() {
        let r = 10.0 * Double.pi / 180
        let cont = OrientationMath.continuousAngle(gx: CGFloat(-cos(r)), gy: CGFloat(sin(r)))
        XCTAssertEqual(cont, 350, accuracy: 0.001)
        XCTAssertEqual(LevelerMath.residualAngle(continuous: cont, sector: 0), -10, accuracy: 0.001)
    }

    func testResidualIsAlwaysTheShortWayRound() {
        for c in stride(from: 0.0, to: 360.0, by: 3.0) {
            for s in [0.0, 90.0, 180.0, 270.0] {
                let r = LevelerMath.residualAngle(continuous: CGFloat(c), sector: CGFloat(s))
                XCTAssertLessThanOrEqual(abs(r), 180)
            }
        }
    }

    // MARK: - fillScale

    func testFillScaleIsUnityWhenLevel() {
        XCTAssertEqual(LevelerMath.fillScale(angleDeg: 0, aspect: 16.0 / 9), 1, accuracy: 1e-9)
    }

    /// s = cos d + sin d * max(W/H, H/W).
    func testFillScaleMatchesTheClosedForm() {
        let a = 16.0 / 9
        for deg in [5.0, 10.0, 15.0, 25.0, 45.0] {
            let d = deg * .pi / 180
            let want = cos(d) + sin(d) * a
            XCTAssertEqual(Double(LevelerMath.fillScale(angleDeg: CGFloat(deg), aspect: CGFloat(a))),
                           want, accuracy: 1e-9)
        }
    }

    func testFillScaleIsSymmetricAndMonotonic() {
        let a: CGFloat = 16.0 / 9
        XCTAssertEqual(LevelerMath.fillScale(angleDeg: -12, aspect: a),
                       LevelerMath.fillScale(angleDeg: 12, aspect: a), accuracy: 1e-9)
        var prev = LevelerMath.fillScale(angleDeg: 0, aspect: a)
        for deg in stride(from: CGFloat(1), through: 45, by: 1) {
            let s = LevelerMath.fillScale(angleDeg: deg, aspect: a)
            XCTAssertGreaterThan(s, prev)
            prev = s
        }
    }

    /// Portrait output (9:16) must zoom exactly as much as landscape — the
    /// formula uses max(W/H, H/W) precisely so the orientation drops out.
    func testFillScaleIgnoresOrientation() {
        XCTAssertEqual(LevelerMath.fillScale(angleDeg: 15, aspect: 16.0 / 9),
                       LevelerMath.fillScale(angleDeg: 15, aspect: 9.0 / 16), accuracy: 1e-9)
    }

    /// The zoom that the owner's 5-15 degree tilt actually costs. 4K oversampling
    /// gives 2x headroom, so 1.43x still lands above 1080p.
    func testFillScaleAtTypicalTilt() {
        XCTAssertEqual(Double(LevelerMath.fillScale(angleDeg: 15, aspect: 16.0 / 9)),
                       1.426, accuracy: 0.002)
    }

    /// Geometric ground truth: map each output corner back into the rotated,
    /// scaled source rect and require it to land inside. Bounding boxes do not
    /// answer this — a rotated rectangle covers far less than its bounds.
    func testFillScaleActuallyCoversTheOutput() {
        let w: CGFloat = 1920, h: CGFloat = 1080
        for deg in stride(from: CGFloat(1), through: 25, by: 1) {
            let s = LevelerMath.fillScale(angleDeg: deg, aspect: w / h)
            let r = deg * .pi / 180
            var slack = CGFloat.greatestFiniteMagnitude
            for cx in [-w / 2, w / 2] {
                for cy in [-h / 2, h / 2] {
                    // corner expressed in the (un-rotated) source frame
                    let x = cx * cos(r) + cy * sin(r)
                    let y = -cx * sin(r) + cy * cos(r)
                    XCTAssertLessThanOrEqual(abs(x), s * w / 2 + 1e-6, "x at \(deg)")
                    XCTAssertLessThanOrEqual(abs(y), s * h / 2 + 1e-6, "y at \(deg)")
                    slack = min(slack, min(s * w / 2 - abs(x), s * h / 2 - abs(y)))
                }
            }
            // and it is minimal: at least one corner sits exactly on an edge
            XCTAssertLessThan(slack, 1e-6, "not minimal at \(deg)")
        }
    }

    // MARK: - clamping

    func testResidualIsClampedSoTheZoomStaysSane() {
        XCTAssertEqual(LevelerMath.clampResidual(60), LevelerMath.maxResidualDeg)
        XCTAssertEqual(LevelerMath.clampResidual(-60), -LevelerMath.maxResidualDeg)
        XCTAssertEqual(LevelerMath.clampResidual(12), 12)
        // Raised 25 -> 45 on 2026-09-05: a steady 45-degree tripod tilt must come
        // out level, so the clamp has to sit above the 50-degree worst-case
        // residual the 5-degree sector hysteresis can produce in transit only.
        XCTAssertEqual(LevelerMath.maxResidualDeg, 45)
        XCTAssertEqual(LevelerMath.clampResidual(30), 30)
    }

    /// Zoom cost at the new clamp, pinned so the trade stays visible: 16:9 at 45
    /// degrees needs cos45 + sin45 * 16/9 = 1.964x. Oversampling 4K into 1080p has
    /// 2.0x of linear headroom, so the worst case still does not upscale.
    func testFillScaleAtTheClampFitsInsideFourKOversampling() {
        let s = LevelerMath.fillScale(angleDeg: 45, aspect: 16.0 / 9)
        XCTAssertEqual(s, 1.964, accuracy: 0.002)
        XCTAssertLessThan(s, 3840.0 / 1920.0)
    }

    /// End-to-end sign check for the physical case described in
    /// `LevelerMath.residualAngle`: the phone rolled 10 degrees CLOCKWISE as seen
    /// from behind it (operator looking at the screen, rear camera at the scene).
    ///
    /// Rolling the body clockwise in that view rotates a world-fixed vector
    /// counter-clockwise in body coordinates, so gravity moves from (-1, 0) to
    /// (-cos10, -sin10). The chain must end in a POSITIVE residual, because
    /// `HorizonLeveler.process` turns the picture clockwise for a positive one
    /// (`rotationAngle: -delta` in CoreImage's counter-clockwise y-up space) and
    /// clockwise is what levels a horizon that appears tilted counter-clockwise.
    func testResidualSignForTenDegreeClockwiseRoll() {
        let r = 10 * CGFloat.pi / 180
        let gx = -cos(r), gy = -sin(r)

        let continuous = OrientationMath.continuousAngle(gx: gx, gy: gy)
        XCTAssertEqual(continuous, 10, accuracy: 0.001)

        let sector = OrientationMath.quantizeAngle(gx: gx, gy: gy, last: 0)
        XCTAssertEqual(sector, 0)

        let residual = LevelerMath.residualAngle(continuous: continuous, sector: sector)
        XCTAssertEqual(residual, 10, accuracy: 0.001)
        XCTAssertGreaterThan(residual, 0, "positive residual = rotate the picture clockwise")
        XCTAssertEqual(LevelerMath.clampResidual(residual), residual, accuracy: 0.001)

        // Mirror case: rolled counter-clockwise -> negative residual.
        let ccw = OrientationMath.continuousAngle(gx: -cos(r), gy: sin(r))
        XCTAssertEqual(LevelerMath.residualAngle(continuous: ccw, sector: 0), -10, accuracy: 0.001)
    }

    // MARK: - smoothing

    func testFirstSampleIsAdoptedImmediately() {
        var s = ResidualSmoother()
        XCTAssertEqual(s.update(target: 9, dt: 1.0 / 30, confidence: 1), 9, accuracy: 1e-9)
    }

    /// One time constant of steady input must close ~63 percent of the gap.
    func testExponentialApproachHitsOneTimeConstant() {
        var s = ResidualSmoother()
        s.update(target: 0, dt: 1.0 / 30, confidence: 1)
        var t: TimeInterval = 0
        while t < LevelerMath.timeConstant {
            s.update(target: 10, dt: 1.0 / 30, confidence: 1)
            t += 1.0 / 30
        }
        XCTAssertEqual(Double(s.value), 6.32, accuracy: 0.35)
    }

    func testSmootherConvergesAndNeverOvershoots() {
        var s = ResidualSmoother()
        s.update(target: 0, dt: 1.0 / 30, confidence: 1)
        for _ in 0..<300 {
            let v = s.update(target: 12, dt: 1.0 / 30, confidence: 1)
            XCTAssertLessThanOrEqual(v, 12.0001)
        }
        // Converges to within the dead band, by construction not past it.
        XCTAssertEqual(Double(s.value), 12, accuracy: Double(LevelerMath.deadBandDeg))
        XCTAssertGreaterThan(Double(s.value), 12 - Double(LevelerMath.deadBandDeg))
    }

    /// Sensor noise below the dead band must not move the rendered angle at all,
    /// otherwise every frame resamples for nothing.
    func testDeadBandFreezesSmallJitter() {
        var s = ResidualSmoother()
        s.update(target: 7, dt: 1.0 / 30, confidence: 1)
        for i in 0..<60 {
            let noise: CGFloat = i % 2 == 0 ? 0.2 : -0.2
            s.update(target: 7 + noise, dt: 1.0 / 30, confidence: 1)
        }
        XCTAssertEqual(Double(s.value), 7, accuracy: 1e-9)
    }

    func testDeadBandDoesNotBlockRealMovement() {
        var s = ResidualSmoother()
        s.update(target: 0, dt: 1.0 / 30, confidence: 1)
        for _ in 0..<200 { s.update(target: 5, dt: 1.0 / 30, confidence: 1) }
        XCTAssertEqual(Double(s.value), 5, accuracy: Double(LevelerMath.deadBandDeg))
    }

    /// Flat phone: the in-plane gravity is noise, so the residual freezes exactly
    /// like the quantised sector does.
    func testFlatPhoneFreezesTheResidual() {
        var s = ResidualSmoother()
        s.update(target: 8, dt: 1.0 / 30, confidence: 1)
        for _ in 0..<100 {
            s.update(target: -40, dt: 1.0 / 30, confidence: 0.05)
        }
        XCTAssertEqual(Double(s.value), 8, accuracy: 1e-9)
    }

    func testSmootherTakesTheShortWayAcrossTheWrap() {
        var s = ResidualSmoother()
        s.update(target: 179, dt: 1.0 / 30, confidence: 1)
        for _ in 0..<400 { s.update(target: -179, dt: 1.0 / 30, confidence: 1) }
        // 179 -> -179 is 2 degrees the short way, never a 358-degree sweep.
        XCTAssertEqual(Double(s.value), -179, accuracy: Double(LevelerMath.deadBandDeg))
    }

    // MARK: - output geometry

    func testOutputFollowsInputOrientation() {
        let target = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(HorizonLeveler.outputSize(source: CGSize(width: 3840, height: 2160),
                                                 target: target),
                       CGSize(width: 1920, height: 1080))
        XCTAssertEqual(HorizonLeveler.outputSize(source: CGSize(width: 2160, height: 3840),
                                                 target: target),
                       CGSize(width: 1080, height: 1920))
    }

    func testOversampledTargetIsOneStepUpOrNothing() {
        XCTAssertEqual(CaptureEngine.oversampledTarget(width: 1920, height: 1080)?.0, 3840)
        XCTAssertEqual(CaptureEngine.oversampledTarget(width: 1080, height: 1920)?.1, 2160)
        XCTAssertEqual(CaptureEngine.oversampledTarget(width: 1280, height: 720)?.0, 1920)
        XCTAssertNil(CaptureEngine.oversampledTarget(width: 3840, height: 2160))
        XCTAssertNil(CaptureEngine.oversampledTarget(width: 640, height: 480))
    }

    /// Preview-only runs at a modest, fixed format and never asks for an encoder
    /// bitrate — the picture is on screen before any Mac has connected.
    func testPreviewParamsAre720p30WithoutBitrate() {
        let p = CaptureEngine.previewParams(cameraId: 2)
        XCTAssertEqual(p.cameraId, 2)
        XCTAssertEqual(p.width, 1280)
        XCTAssertEqual(p.height, 720)
        XCTAssertEqual(p.fps, 30)
        XCTAssertEqual(p.bitrateKbps, 0)
        // 720p preview must not drag the 4K oversampling path in: that only
        // exists for the levelled encode.
        XCTAssertEqual(CaptureEngine.oversampledTarget(width: p.width, height: p.height)?.0, 1920)
    }

    // MARK: - render path

    /// Whether CoreImage can write biplanar 420v decides the render path. The
    /// probe must give a definite answer on whatever runs the tests, and the
    /// leveller must report the same value it probed.
    func testRenderPathProbeIsDecisive() throws {
        let leveler = try XCTUnwrap(HorizonLeveler(), "no Metal device")
        XCTAssertTrue([.nv12, .bgra].contains(leveler.path))
        XCTAssertEqual(leveler.snapshot.path, leveler.path)
    }

    /// End-to-end through the real CIContext: a levelled frame comes out at the
    /// requested size, carries the source timestamp and keeps the 709 tags.
    func testProcessProducesTargetSizedFrameWithSourceTiming() throws {
        let leveler = try XCTUnwrap(HorizonLeveler(), "no Metal device")
        let src = try XCTUnwrap(HorizonLeveler.makeBuffer(
            1280, 720, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange))
        HorizonLeveler.fillLuma(src, 200)
        HorizonLeveler.tag709(src)

        var desc: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: src,
                                                     formatDescriptionOut: &desc)
        let pts = CMTime(value: 12_345, timescale: 600)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 20, timescale: 600),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: src,
                                                 formatDescription: try XCTUnwrap(desc),
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sample)

        let out = try XCTUnwrap(leveler.process(try XCTUnwrap(sample), residualDeg: 8,
                                                target: CGSize(width: 1920, height: 1080)))
        let buf = try XCTUnwrap(CMSampleBufferGetImageBuffer(out))
        XCTAssertEqual(CVPixelBufferGetWidth(buf), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(buf), 1080)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(out), pts)
        let matrix = CVBufferGetAttachment(buf, kCVImageBufferYCbCrMatrixKey, nil)?
            .takeUnretainedValue() as? NSString
        XCTAssertEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2 as NSString)
        XCTAssertEqual(leveler.snapshot.lastResidualDeg, 8, accuracy: 1e-6)
        XCTAssertGreaterThan(leveler.snapshot.avgMs, 0)
    }
}
