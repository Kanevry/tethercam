import AVFoundation
import CoreMedia
import Foundation

/// AVCaptureSession wrapper: camera enumeration with stable ids, format choice
/// nearest to the requested width/height/fps, NV12 video-range output on a
/// serial queue.
///
/// Ids are assigned once at construction in a fixed order (back wide,
/// back ultra-wide, back tele, front) so the id the Mac sends in START always
/// means the same physical camera for the lifetime of the process.
public final class CaptureEngine: NSObject {

    public struct Camera {
        public let id: UInt8
        public let device: AVCaptureDevice
        public let descriptor: CameraDescriptor
    }

    public enum CaptureError: Error {
        case denied
        case noSuchCamera(UInt8)
        case cannotAddInput
        case cannotAddOutput
        /// `switchCamera` was asked to keep a format nobody negotiated.
        case notStreaming
    }

    public let cameras: [Camera]
    public let session = AVCaptureSession()

    /// Format the session runs at while nobody streams. Modest on purpose: the
    /// preview only has to fill a phone screen, and 720p30 keeps the phone cool
    /// while it waits — sometimes for an hour before the Mac ever connects.
    public static let previewWidth: UInt16 = 1280
    public static let previewHeight: UInt16 = 720
    public static let previewFps: UInt16 = 30

    /// Parameters for preview-only operation. Pure, so the format contract is
    /// testable without a camera. `bitrateKbps` is 0: nothing is encoded here.
    public static func previewParams(cameraId: UInt8) -> StartParams {
        StartParams(cameraId: cameraId, width: previewWidth, height: previewHeight,
                    fps: previewFps, bitrateKbps: 0)
    }

    /// True between a successful `start` and the next `stop`. While false the
    /// session may well be running — preview-only — but no buffer reaches the
    /// encoder and the leveller stays idle.
    public var isEncoding: Bool {
        motionLock.lock(); defer { motionLock.unlock() }
        return encodingFlag
    }
    private var encodingFlag = false
    private func setEncoding(_ on: Bool) {
        motionLock.lock(); encodingFlag = on; motionLock.unlock()
    }
    /// Lens the preview falls back to after STOP or a disconnect.
    private var previewCameraId: UInt8 = 0

    /// Rotation source of truth. `true` (default) follows the device's horizon
    /// via `AVCaptureDevice.RotationCoordinator`, so the encoded frame is upright
    /// no matter how the phone sits in the tripod mount. `false` pins the angle
    /// to `manualRotationAngle`.
    public var autoRotation = true { didSet { applyRotation() } }
    /// Manual angle in degrees, one of 0/90/180/270. Only read when
    /// `autoRotation` is false.
    public var manualRotationAngle: CGFloat = 0 { didSet { applyRotation() } }

    /// Set by the SwiftUI preview so the coordinator can also keep the on-screen
    /// preview level. Weak: the layer belongs to the view hierarchy.
    public weak var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { rebuildRotationCoordinator() }
    }

    /// Gravity-based orientation. Source of truth for the *capture* angle in
    /// auto mode; the RotationCoordinator stays on board for the preview layer
    /// and as a cross-check in the log. See OrientationSensor.swift for why the
    /// coordinator alone is not enough on a steeply tilted tripod.
    public let orientation = OrientationSensor()

    /// Continuous horizon levelling. The connection's `videoRotationAngle` only
    /// knows 0/90/180/270, so a tripod head that sits 8 degrees off level ships
    /// an 8-degree-tilted picture. With this on, the residual between the
    /// continuous gravity angle and the applied sector is rotated away on the GPU
    /// (`HorizonLeveler`) before the frame reaches the encoder — Continuity-Camera
    /// behaviour. Only effective in auto-rotation mode: a manually pinned angle is
    /// a deliberate choice and is left alone.
    public var horizonLeveling = true {
        didSet {
            guard horizonLeveling != oldValue else { return }
            resetLeveling()
        }
    }

    /// Format actually delivered by the camera. Differs from `activeFormat` when
    /// the leveller oversamples (4K source for a 1080p output).
    public private(set) var sourceFormat: (width: UInt16, height: UInt16, fps: UInt16)?
    /// Live leveller telemetry for the diagnostics row. Written on the capture
    /// queue, read on main — hence the lock.
    public var levelerTelemetry: HorizonLeveler.Telemetry {
        motionLock.lock(); defer { motionLock.unlock() }
        return storedTelemetry
    }
    private var storedTelemetry = HorizonLeveler.Telemetry()

    private lazy var leveler: HorizonLeveler? = HorizonLeveler()
    private var smoother = ResidualSmoother()
    /// Output size the Mac asked for, in landscape orientation.
    private var requestedOutput = CGSize(width: 1920, height: 1080)
    /// Latest raw motion sample, written on main, read on the sample queue.
    private var motion = (continuous: CGFloat(90), confidence: CGFloat(0), sector: CGFloat(90))
    /// Angle `applyRotation()` last wrote to the video connection. Written on
    /// main, read on `sessionQueue` — hence guarded by `motionLock`.
    private var appliedCaptureAngle: CGFloat = 90
    private let motionLock = NSLock()
    private var lastFrameTime: CFAbsoluteTime = 0
    private var statWindowStart: CFAbsoluteTime = 0
    private var statFrames = 0
    private var lastParams: StartParams?
    private var oversampling = false
    private var oversamplingDisabled = false
    private let sessionQueue = DispatchQueue(label: "at.gotzendorfer.usbcam.session")
    private let sampleQueue = DispatchQueue(label: "at.gotzendorfer.usbcam.samples")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    /// Called on `sampleQueue` for every delivered frame.
    public var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    /// Actually negotiated format after `start` — may differ from the request.
    public private(set) var activeFormat: (width: UInt16, height: UInt16, fps: UInt16)?

    public override init() {
        cameras = CaptureEngine.discover()
        super.init()
        orientation.onCaptureAngleChange = { [weak self] _ in self?.applyRotation() }
        orientation.onSample = { [weak self] cont, m in
            guard let self else { return }
            let sector = self.desiredCaptureAngle()
            self.motionLock.lock()
            self.motion = (cont, m, sector)
            self.motionLock.unlock()
        }
        orientation.start()
    }

    public var descriptors: [CameraDescriptor] { cameras.map(\.descriptor) }

    private static func discover() -> [Camera] {
        // Fixed probe order → stable ids 0..n. Devices absent on the hardware
        // are simply skipped, so an iPhone without a tele lens yields 0,1,2.
        // Names are wire literals shown verbatim in OBS; the app UI localizes
        // them via CameraDescriptor.displayName (CameraDisplayName.swift).
        let wanted: [(AVCaptureDevice.DeviceType, AVCaptureDevice.Position, String)] = [
            (.builtInWideAngleCamera, .back, "Back Wide"),
            (.builtInUltraWideCamera, .back, "Back Ultra Wide"),
            (.builtInTelephotoCamera, .back, "Back Telephoto"),
            (.builtInWideAngleCamera, .front, "Front"),
        ]
        var out: [Camera] = []
        var nextId: UInt8 = 0
        for (type, position, name) in wanted {
            let s = AVCaptureDevice.DiscoverySession(deviceTypes: [type],
                                                     mediaType: .video,
                                                     position: position)
            guard let dev = s.devices.first else { continue }
            out.append(Camera(id: nextId, device: dev,
                              descriptor: CameraDescriptor(
                                id: nextId,
                                position: position == .front ? .front : .back,
                                name: name)))
            nextId &+= 1
        }
        return out
    }

    public func requestAccess(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { done(ok) } }
        default: done(false)
        }
    }

    /// Configures and starts the session. Completion runs on `sessionQueue`.
    public func start(_ params: StartParams, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let cam = cameras.first(where: { $0.id == params.cameraId }) else {
            completion(.failure(CaptureError.noSuchCamera(params.cameraId)))
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            completion(.failure(CaptureError.denied))
            return
        }
        lastParams = params
        previewCameraId = cam.id
        setEncoding(true)
        sessionQueue.async { [self] in
            do {
                session.beginConfiguration()
                session.sessionPreset = .inputPriority   // format is chosen manually below

                // Swap the input only when the lens really changes: coming out of
                // preview on the same camera, keeping it alive means the picture
                // never blacks out across the START.
                if currentInput?.device !== cam.device {
                    if let old = currentInput { session.removeInput(old) }
                    let input = try AVCaptureDeviceInput(device: cam.device)
                    guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
                    session.addInput(input)
                    currentInput = input
                }

                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                ]
                if !session.outputs.contains(videoOutput) {
                    guard session.canAddOutput(videoOutput) else { throw CaptureError.cannotAddOutput }
                    session.addOutput(videoOutput)
                    videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
                }

                motionLock.lock()
                requestedOutput = CGSize(width: Int(params.width), height: Int(params.height))
                motionLock.unlock()
                resetLeveling()
                statWindowStart = CFAbsoluteTimeGetCurrent()
                statFrames = 0
                let chosen = try configureDevice(cam.device, params)
                sourceFormat = chosen
                // With oversampling the camera runs at 4K while the encoder still
                // gets 1080p — CONFIG must announce what leaves the leveller.
                activeFormat = levelingActive
                    ? (params.width, params.height, chosen.2)
                    : chosen

                if let c = videoOutput.connection(with: .video) {
                    c.isVideoMirrored = false
                }
                applyStoredRotation()

                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                currentDevice = cam.device
                DispatchQueue.main.async { [self] in rebuildRotationCoordinator() }
                completion(.success(()))
            } catch {
                session.commitConfiguration()
                setEncoding(false)
                completion(.failure(error))
            }
        }
    }

    /// Ends encoding and falls back to preview-only. The session keeps running:
    /// a black screen between two takes is the thing this app is judged on, and
    /// restarting AVCaptureSession costs about a second of black.
    public func stop() {
        setEncoding(false)
        sessionQueue.async { [self] in
            // A START that arrived while this block waited (the restart path in
            // ServerStateMachine emits stopCapture + startCapture for a format
            // change) has already flipped encoding back on and queued its own
            // configuration behind us. Dropping to the preview format here would
            // undo it and leak a 720p buffer into the encoder.
            guard !isEncoding else { return }
            activeFormat = nil
            sourceFormat = nil
            resetLeveling()
            oversampling = false
            if let cam = cameras.first(where: { $0.id == previewCameraId }) ?? cameras.first {
                configurePreview(cam)
            } else if session.isRunning {
                session.stopRunning()
                currentDevice = nil
                DispatchQueue.main.async { [self] in
                    rotationObservation = nil
                    rotationCoordinator = nil
                }
            }
        }
    }

    /// Swaps the lens under a running take, keeping the negotiated format.
    /// One configuration transaction: input out, input in, device format
    /// re-applied from `lastParams`. Never touches `configurePreview`, so the
    /// encoder never sees a 720p preview buffer in between (the CONFIG leak
    /// behind obs-iphone-usb-cam#4). Completion runs on `sessionQueue`.
    public func switchCamera(to cameraId: UInt8,
                             completion: @escaping (Result<Void, Error>) -> Void) {
        guard let cam = cameras.first(where: { $0.id == cameraId }) else {
            completion(.failure(CaptureError.noSuchCamera(cameraId)))
            return
        }
        guard let params = lastParams, isEncoding else {
            // Nothing negotiated: there is no format to keep. The caller falls
            // back to a plain start.
            completion(.failure(CaptureError.notStreaming))
            return
        }
        var next = params
        next.cameraId = cam.id
        lastParams = next
        previewCameraId = cam.id
        sessionQueue.async { [self] in
            guard currentInput?.device !== cam.device else {
                completion(.success(()))
                return
            }
            let previous = currentInput
            session.beginConfiguration()
            do {
                if let old = previous { session.removeInput(old) }
                let input = try AVCaptureDeviceInput(device: cam.device)
                guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
                session.addInput(input)
                currentInput = input
                resetLeveling()
                let chosen = try configureDevice(cam.device, next)
                sourceFormat = chosen
                activeFormat = levelingActive
                    ? (next.width, next.height, chosen.2)
                    : chosen
                if let c = videoOutput.connection(with: .video) {
                    c.isVideoMirrored = false
                }
                applyStoredRotation()
                session.commitConfiguration()
                currentDevice = cam.device
                DispatchQueue.main.async { [self] in rebuildRotationCoordinator() }
                completion(.success(()))
            } catch {
                // Put the old lens back so the fallback stop/start has a sane
                // session to work from.
                if let input = currentInput, input !== previous { session.removeInput(input) }
                if let old = previous, session.canAddInput(old) {
                    session.addInput(old)
                    currentInput = old
                } else {
                    // The old input could not be re-attached: say so, or a later
                    // start() would believe the right input is still present.
                    currentInput = nil
                }
                session.commitConfiguration()
                completion(.failure(error))
            }
        }
    }

    /// Starts (or switches) the preview-only session. No-op while streaming —
    /// a running take owns the session, and the state machine restarts it with
    /// the new lens on its own. Safe to call repeatedly.
    public func startPreview(cameraId: UInt8? = nil) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        let wanted = cameraId ?? previewCameraId
        guard let cam = cameras.first(where: { $0.id == wanted }) ?? cameras.first else { return }
        previewCameraId = cam.id
        sessionQueue.async { [self] in
            guard !isEncoding else { return }
            configurePreview(cam)
        }
    }

    /// sessionQueue only. Runs the given lens at the preview format with the
    /// video-data output detached, so no buffer is ever delivered and neither
    /// leveller nor encoder do any work.
    private func configurePreview(_ cam: Camera) {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        if currentInput?.device !== cam.device {
            if let old = currentInput { session.removeInput(old) }
            do {
                let input = try AVCaptureDeviceInput(device: cam.device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    NSLog("[usbcam] preview: cannot add input for cam=%d", Int(cam.id))
                    return
                }
                session.addInput(input)
                currentInput = input
            } catch {
                session.commitConfiguration()
                NSLog("[usbcam] preview input failed: %@", "\(error)" as NSString)
                return
            }
        }
        if session.outputs.contains(videoOutput) { session.removeOutput(videoOutput) }
        _ = try? configureDevice(cam.device, Self.previewParams(cameraId: cam.id))
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        currentDevice = cam.device
        NSLog("[usbcam] preview-only cam=%d %dx%d@%d", Int(cam.id),
              Int(Self.previewWidth), Int(Self.previewHeight), Int(Self.previewFps))
        DispatchQueue.main.async { [self] in rebuildRotationCoordinator() }
    }

    // MARK: - Rotation

    /// Angle that should be written to the video-data-output connection.
    /// Rotating there (rather than after the fact in the receiver) means the
    /// encoder sees an upright buffer, so a portrait mount legitimately yields a
    /// portrait 1080x1920 stream — the encoder notices the changed dimensions
    /// and sends a fresh CONFIG.
    private func desiredCaptureAngle() -> CGFloat {
        guard autoRotation else { return manualRotationAngle }
        // Gravity first. The coordinator is only the fallback for the window
        // before the first motion sample (or a device without an accelerometer),
        // because its horizon-level angle freezes when no horizon is in frame.
        if orientation.hasFix { return orientation.captureAngle }
        return rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? manualRotationAngle
    }

    /// Recreates the coordinator for the currently running device. Must run on
    /// the main queue because it touches the preview layer.
    private func rebuildRotationCoordinator() {
        rotationObservation = nil
        rotationCoordinator = nil
        guard let device = currentDevice else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device,
                                                              previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyRotation() }
            }
        applyRotation()
    }

    /// Writes the current angle to both connections. Safe to call repeatedly —
    /// AVFoundation ignores a write of the value already in place.
    private func applyRotation() {
        let apply = { [self] in
            let angle = desiredCaptureAngle()
            motionLock.lock(); appliedCaptureAngle = angle; motionLock.unlock()
            if let c = videoOutput.connection(with: .video),
               c.isVideoRotationAngleSupported(angle) {
                c.videoRotationAngle = angle
            }
            let source = autoRotation ? (orientation.hasFix ? "sensor" : "coordinator") : "manual"
            // Cross-check: with the phone held normally both numbers must agree.
            // They diverge exactly in the steep-tilt case this sensor exists for.
            NSLog("[usbcam] rotation angle=%.0f source=%@ m=%.2f cont=%.0f coordinator=%.0f auto=%d",
                  Double(angle), source as NSString,
                  Double(orientation.confidence), Double(orientation.continuousAngle),
                  Double(rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? -1),
                  autoRotation ? 1 : 0)
            if let pc = previewLayer?.connection {
                let pa = autoRotation
                    ? (rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? angle)
                    : angle
                if pc.isVideoRotationAngleSupported(pa) { pc.videoRotationAngle = pa }
            }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    /// sessionQueue-only. Writes the last known angle to the video connection
    /// inside the running configuration transaction.
    ///
    /// A fresh connection (new input, or the output re-added after preview)
    /// starts at angle 0. Waiting for `rebuildRotationCoordinator()` to hop to
    /// main and call `applyRotation()` leaves a window in which a portrait mount
    /// delivers landscape 1920x1080 buffers although CONFIG announced 1080x1920:
    /// `HevcEncoder.encode` then rebuilds the VT session on the transposed size
    /// and a spurious CONFIG pair goes out. So the angle is applied here, before
    /// `commitConfiguration`, from `appliedCaptureAngle` — the value the previous
    /// connection already carried. `desiredCaptureAngle()` cannot be used: it
    /// reads main-only state (`OrientationSensor`'s published values and the
    /// RotationCoordinator).
    private func applyStoredRotation() {
        motionLock.lock()
        let angle = appliedCaptureAngle
        motionLock.unlock()
        guard let c = videoOutput.connection(with: .video),
              c.isVideoRotationAngleSupported(angle) else { return }
        c.videoRotationAngle = angle
    }

    /// Picks the format whose dimensions and frame-rate range are nearest to the
    /// request, then locks the frame duration to the requested fps.
    private func configureDevice(_ device: AVCaptureDevice,
                                 _ p: StartParams) throws -> (UInt16, UInt16, UInt16) {
        let wantW = Int32(p.width), wantH = Int32(p.height), wantFps = Double(p.fps)

        func score(_ f: AVCaptureDevice.Format, _ w: Int32, _ h: Int32) -> Double {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            // Prefer NV12 video-range so no pixel conversion is needed.
            let subPenalty = sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 0.0 : 1_000_000.0
            let pixelDelta = abs(Double(d.width - w)) + abs(Double(d.height - h))
            let fpsDelta: Double = f.videoSupportedFrameRateRanges.map {
                if wantFps < $0.minFrameRate { return $0.minFrameRate - wantFps }
                if wantFps > $0.maxFrameRate { return wantFps - $0.maxFrameRate }
                return 0
            }.min() ?? 1000
            return pixelDelta + fpsDelta * 100 + subPenalty
        }

        func pick(_ w: Int32, _ h: Int32) -> AVCaptureDevice.Format? {
            device.formats.min(by: { score($0, w, h) < score($1, w, h) })
        }
        /// A format only counts as an oversampling win when it really is at least
        /// as large as asked for *and* runs at the requested fps — a 4K format
        /// capped at 24 fps would silently drop the stream to 24.
        func covers(_ f: AVCaptureDevice.Format, _ w: Int32, _ h: Int32) -> Bool {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            let fpsOk = f.videoSupportedFrameRateRanges.contains {
                wantFps >= $0.minFrameRate - 0.01 && wantFps <= $0.maxFrameRate + 0.01
            }
            return d.width >= w && d.height >= h && fpsOk
                && sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }

        var chosen: AVCaptureDevice.Format?
        oversampling = false
        if levelingActive, !oversamplingDisabled,
           let up = Self.oversampledTarget(width: p.width, height: p.height),
           let candidate = pick(up.0, up.1), covers(candidate, up.0, up.1) {
            // Level + crop out of a larger source, so the fill zoom costs no
            // resolution: 1080p out of 4K survives a 1.43x crop at 15 degrees.
            chosen = candidate
            oversampling = true
        }
        guard let best = chosen ?? pick(wantW, wantH) else {
            throw CaptureError.noSuchCamera(p.cameraId)
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = best
        // BT.709 primaries at the source; the encoder tags the same (spec section 4).
        if device.activeFormat.supportedColorSpaces.contains(.sRGB) {
            device.activeColorSpace = .sRGB
        }
        let range = best.videoSupportedFrameRateRanges.first
        let fps = min(max(wantFps, range?.minFrameRate ?? wantFps), range?.maxFrameRate ?? wantFps)
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        let d = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
        NSLog("[usbcam] capture format %dx%d@%.0f oversampling=%d output=%dx%d leveling=%d",
              Int(d.width), Int(d.height), fps, oversampling ? 1 : 0,
              Int(p.width), Int(p.height), levelingActive ? 1 : 0)
        return (UInt16(clamping: Int(d.width)), UInt16(clamping: Int(d.height)),
                UInt16(clamping: Int(fps.rounded())))
    }
}

// MARK: - Horizon levelling

extension CaptureEngine {

    /// Hands the latest counters to the UI side under the lock.
    fileprivate func publish(_ t: HorizonLeveler.Telemetry) {
        motionLock.lock()
        storedTelemetry = t
        motionLock.unlock()
    }

    /// Telemetry snapshot for the once-per-second STATS message
    /// (`protocol/PROTOCOL.md` section 4.8). Safe from any queue.
    ///
    /// `residual` is the value the leveller **actually applied** (smoothed and
    /// clamped), not the geometric `continuous - sector`. The geometric one is
    /// derivable from the two angles that travel alongside it, so sending the
    /// applied one makes a clamp hit or a smoothing lag visible instead of
    /// invisible: `residual != angle - sector` means the leveller is not covering
    /// the tilt.
    public func statsSnapshot() -> DeviceStats {
        motionLock.lock()
        let m = motion
        let t = storedTelemetry
        motionLock.unlock()

        var flags: UInt8 = 0
        if autoRotation { flags |= DeviceStats.flagAutoRotation }
        if horizonLeveling { flags |= DeviceStats.flagHorizonLeveling }
        if oversampling { flags |= DeviceStats.flagOversampling }
        if m.confidence < OrientationMath.flatThreshold { flags |= DeviceStats.flagFlatHold }

        let src = sourceFormat ?? activeFormat
        let hasOut = t.outputSize.width > 0 && t.outputSize.height > 0
        let outW = hasOut ? Int(t.outputSize.width) : Int(activeFormat?.width ?? 0)
        let outH = hasOut ? Int(t.outputSize.height) : Int(activeFormat?.height ?? 0)

        return DeviceStats(continuousDeg: Double(m.continuous),
                           sector: Double(m.sector),
                           residualDeg: Double(t.lastResidualDeg),
                           gravityM: Double(m.confidence),
                           levelerMs: t.avgMs,
                           droppedFrames: t.droppedFrames,
                           sourceWidth: Int(src?.width ?? 0),
                           sourceHeight: Int(src?.height ?? 0),
                           outputWidth: outW, outputHeight: outH,
                           flags: flags,
                           cameraId: lastParams?.cameraId ?? 0)
    }

    /// Drops the smoothed residual and the pixel pool. Safe from any queue:
    /// the smoother sits under `motionLock`, the leveller under its own.
    fileprivate func resetLeveling() {
        motionLock.lock()
        smoother.reset()
        motionLock.unlock()
        leveler?.reset()
    }

    /// Levelling only runs in auto mode: a manually pinned angle is the user
    /// overriding the sensor, and rotating on top of that would fight them.
    var levelingActive: Bool { isEncoding && horizonLeveling && autoRotation && leveler != nil }

    /// One format step up, so the fill zoom crops out of surplus pixels.
    /// `nil` for anything else — 4K in, 4K out has nothing to oversample from.
    static func oversampledTarget(width: UInt16, height: UInt16) -> (Int32, Int32)? {
        let long = max(width, height), short = min(width, height)
        switch (long, short) {
        case (1920, 1080): return (3840, 2160)
        case (1280, 720): return (1920, 1080)
        default: return nil
        }
    }

    /// Rolling delivery log, every 5 seconds. Also the budget watchdog: if the
    /// leveller cannot hold the frame time while oversampling, the source drops
    /// back to the requested size rather than starving the encoder.
    fileprivate func tickStats(levelled: Bool) {
        statFrames += 1
        let now = CFAbsoluteTimeGetCurrent()
        if statWindowStart == 0 { statWindowStart = now; return }
        let elapsed = now - statWindowStart
        guard elapsed >= 5 else { return }
        let fps = Double(statFrames) / elapsed
        let t = leveler?.snapshot
        let src = sourceFormat.map { "\($0.width)x\($0.height)" } ?? "-"
        let out = t.map { "\(Int($0.outputSize.width))x\(Int($0.outputSize.height))" } ?? src
        NSLog("[usbcam] leveler avg=%.2fms src=%@ out=%@ fps=%.1f dropped=%d residual=%.1f path=%@ leveling=%d",
              t?.avgMs ?? 0, src as NSString, out as NSString, fps,
              t?.droppedFrames ?? 0, Double(t?.lastResidualDeg ?? 0),
              (t?.path.rawValue ?? "-") as NSString, levelled ? 1 : 0)
        if oversampling, let t, t.avgMs > 12 { downgradeOversampling(avgMs: t.avgMs) }
        statWindowStart = now
        statFrames = 0
    }

    /// 4K in is a nice-to-have; 30 fps is not. Over budget, the source format
    /// falls back to the requested size and stays there for this session.
    private func downgradeOversampling(avgMs: Double) {
        oversamplingDisabled = true
        oversampling = false
        NSLog("[usbcam] leveler over budget (%.2f ms/frame) - oversampling disabled", avgMs)
        guard let device = currentDevice, let p = lastParams else { return }
        sessionQueue.async { [self] in
            session.beginConfiguration()
            if let f = try? configureDevice(device, p) { sourceFormat = f }
            session.commitConfiguration()
            leveler?.reset()
        }
    }
}

extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        // Belt and braces: the output is detached in preview-only mode, so a
        // buffer arriving here after STOP is a stale in-flight one. Drop it.
        guard isEncoding else { return }
        guard levelingActive, let leveler else {
            onSampleBuffer?(sampleBuffer)
            tickStats(levelled: false)
            return
        }
        motionLock.lock()
        let m = motion
        let target = requestedOutput
        motionLock.unlock()

        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime == 0 ? 1.0 / 30 : now - lastFrameTime
        lastFrameTime = now

        let raw = LevelerMath.residualAngle(continuous: m.continuous, sector: m.sector)
        motionLock.lock()
        let smoothed = smoother.update(target: raw, dt: dt, confidence: m.confidence)
        motionLock.unlock()

        // A dropped frame is dropped, not queued and not passed through raw: the
        // unlevelled buffer has the source geometry (4K when oversampling) and
        // would make the encoder rebuild its session for one frame.
        guard let out = leveler.process(sampleBuffer, residualDeg: smoothed,
                                        target: target) else {
            publish(leveler.snapshot)
            return
        }
        publish(leveler.snapshot)
        onSampleBuffer?(out)
        tickStats(levelled: true)
    }
}
