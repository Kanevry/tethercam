import Combine
import CoreGraphics
import CoreMotion
import Foundation

/// Gravity-based capture orientation.
///
/// `AVCaptureDevice.RotationCoordinator` derives its angle from the *horizon*.
/// On a tripod that points steeply up or down there is no horizon in frame, the
/// coordinator's value freezes at whatever it last saw, and the encoded picture
/// comes out sideways. Gravity has no such blind spot: the accelerometer keeps
/// reporting a usable in-plane component until the device is almost perfectly
/// flat, and only then do we hold the last known angle.
///
/// All math lives in `OrientationMath` so it can be unit-tested without a device.
public enum OrientationMath {

    /// Below this in-plane gravity magnitude the phone lies (or points) flat and
    /// the roll angle is numerically meaningless — hold the last angle instead.
    public static let flatThreshold: CGFloat = 0.12

    /// How far past a 45-degree sector boundary the continuous angle must travel
    /// before the quantised angle follows. Prevents flapping at the boundary.
    public static let hysteresisMargin: CGFloat = 15

    /// In-plane gravity magnitude — the confidence of the roll estimate.
    /// 1.0 = device vertical (screen plane parallel to gravity), 0.0 = flat.
    public static func magnitude(gx: CGFloat, gy: CGFloat) -> CGFloat {
        (gx * gx + gy * gy).squareRoot()
    }

    /// Continuous rotation angle in degrees that has to be written to the
    /// capture connection, derived from the gravity vector in device space.
    ///
    /// CoreMotion device axes: +x right along the short edge, +y up along the
    /// long edge (towards the front camera), +z out of the screen. Gravity
    /// points *down* in world space, so:
    ///
    /// | pose (physical)                  | gravity (x,y) | wanted angle |
    /// |----------------------------------|---------------|--------------|
    /// | portrait, upright                | ( 0, -1)      |  90          |
    /// | landscape, charge port right     | (-1,  0)      |   0          |
    /// | landscape, charge port left      | ( 1,  0)      | 180          |
    /// | portrait, upside down            | ( 0,  1)      | 270          |
    ///
    /// That is the pre-iPhone-17 `videoRotationAngle` convention
    /// (0 = landscapeRight, 90 = portrait, 180 = landscapeLeft,
    /// 270 = portraitUpsideDown) which the iPhone 15 Pro Max uses.
    ///
    /// `atan2(gx, gy)` yields 180 / 270 / 90 / 0 for the four rows above, so the
    /// wanted angle is `270 - atan2(gx, gy)` folded into [0, 360).
    public static func continuousAngle(gx: CGFloat, gy: CGFloat) -> CGFloat {
        let deg = atan2(gx, gy) * 180 / .pi
        return wrap360(270 - deg)
    }

    /// Nearest multiple of 90 in [0, 360).
    public static func snap(_ angle: CGFloat) -> CGFloat {
        wrap360((angle / 90).rounded() * 90)
    }

    /// Quantised capture angle with hysteresis and flat fallback.
    ///
    /// - Returns `last` when the device is too flat to measure roll.
    /// - Returns `last` while the continuous angle is within
    ///   45 + `hysteresisMargin` degrees of it, i.e. the boundary must be
    ///   overshot by 15 degrees before the sector changes.
    /// - Otherwise snaps to the nearest multiple of 90.
    ///
    /// Pure function: the 300 ms dwell time is enforced by `OrientationSensor`,
    /// not here, because it needs a clock.
    public static func quantizeAngle(gx: CGFloat, gy: CGFloat, last: CGFloat) -> CGFloat {
        guard magnitude(gx: gx, gy: gy) >= flatThreshold else { return last }
        let continuous = continuousAngle(gx: gx, gy: gy)
        let anchored = snap(last)
        if angularDistance(continuous, anchored) <= 45 + hysteresisMargin { return anchored }
        return snap(continuous)
    }

    /// Shortest absolute distance between two angles in degrees (0...180).
    public static func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let d = wrap360(a - b)
        return d > 180 ? 360 - d : d
    }

    public static func wrap360(_ a: CGFloat) -> CGFloat {
        var v = a.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }
}

/// Publishes a stable capture angle derived from CoreMotion gravity.
///
/// Updates are delivered on the main queue; `captureAngle` only changes after a
/// new sector has been held for `dwell` seconds, so a swing through a boundary
/// does not toggle the encoder geometry.
public final class OrientationSensor: ObservableObject {

    /// Quantised angle (0/90/180/270) for the capture connection.
    @Published public private(set) var captureAngle: CGFloat = 90
    /// Unquantised roll angle in degrees — diagnostics only.
    @Published public private(set) var continuousAngle: CGFloat = 90
    /// In-plane gravity magnitude, 0...1. Below `flatThreshold` the angle holds.
    @Published public private(set) var confidence: CGFloat = 0
    /// Raw gravity vector in device space.
    @Published public private(set) var gravity: SIMD3<Double> = .init(0, -1, 0)
    /// False until the first usable (non-flat) sample arrived.
    @Published public private(set) var hasFix = false

    /// Fired on the main queue whenever `captureAngle` actually changes.
    public var onCaptureAngleChange: ((CGFloat) -> Void)?

    public var isAvailable: Bool { motion.isDeviceMotionAvailable || motion.isAccelerometerAvailable }

    private let motion = CMMotionManager()
    private let dwell: TimeInterval = 0.3
    private var pendingAngle: CGFloat?
    private var pendingSince: TimeInterval = 0
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
                guard let self, let dm else { return }
                let g = dm.gravity
                self.ingest(SIMD3(g.x, g.y, g.z), at: ProcessInfo.processInfo.systemUptime)
            }
        } else if motion.isAccelerometerAvailable {
            // Fallback: raw acceleration, low-pass filtered towards gravity.
            motion.accelerometerUpdateInterval = 0.1
            var filtered = SIMD3<Double>(0, -1, 0)
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                let raw = SIMD3(a.x, a.y, a.z)
                filtered = filtered * 0.8 + raw * 0.2
                self.ingest(filtered, at: ProcessInfo.processInfo.systemUptime)
            }
        } else {
            running = false
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        pendingAngle = nil
    }

    /// Testable ingest path. `now` is a monotonic seconds clock.
    public func ingest(_ g: SIMD3<Double>, at now: TimeInterval) {
        gravity = g
        let gx = CGFloat(g.x), gy = CGFloat(g.y)
        let m = OrientationMath.magnitude(gx: gx, gy: gy)
        confidence = m
        guard m >= OrientationMath.flatThreshold else {
            // Flat: keep the last known angle, drop any pending switch.
            pendingAngle = nil
            return
        }
        continuousAngle = OrientationMath.continuousAngle(gx: gx, gy: gy)

        guard hasFix else {
            // First usable sample: adopt immediately, no dwell.
            hasFix = true
            setAngle(OrientationMath.snap(continuousAngle))
            return
        }

        let candidate = OrientationMath.quantizeAngle(gx: gx, gy: gy, last: captureAngle)
        guard candidate != captureAngle else { pendingAngle = nil; return }
        if pendingAngle != candidate {
            pendingAngle = candidate
            pendingSince = now
        } else if now - pendingSince >= dwell {
            pendingAngle = nil
            setAngle(candidate)
        }
    }

    private func setAngle(_ a: CGFloat) {
        guard a != captureAngle else { return }
        captureAngle = a
        onCaptureAngleChange?(a)
    }
}

// TODO: optional "Horizont ausrichten (stufenlos)" — rotate the pixel buffer by
// `continuousAngle` with CoreImage (CIImage transform + crop to the same aspect,
// rendered into an NV12 pool via CIContext) before handing it to the encoder.
// Deliberately not implemented: it costs a full per-frame GPU round trip plus a
// second NV12 pool, and the quantised angle already fixes the reported bug.
