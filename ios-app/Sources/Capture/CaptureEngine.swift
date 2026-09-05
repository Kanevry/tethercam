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
    }

    public let cameras: [Camera]
    public let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "at.gotzendorfer.usbcam.session")
    private let sampleQueue = DispatchQueue(label: "at.gotzendorfer.usbcam.samples")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?

    /// Called on `sampleQueue` for every delivered frame.
    public var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    /// Actually negotiated format after `start` — may differ from the request.
    public private(set) var activeFormat: (width: UInt16, height: UInt16, fps: UInt16)?

    public override init() {
        cameras = CaptureEngine.discover()
        super.init()
    }

    public var descriptors: [CameraDescriptor] { cameras.map(\.descriptor) }

    private static func discover() -> [Camera] {
        // Fixed probe order → stable ids 0..n. Devices absent on the hardware
        // are simply skipped, so an iPhone without a tele lens yields 0,1,2.
        let wanted: [(AVCaptureDevice.DeviceType, AVCaptureDevice.Position, String)] = [
            (.builtInWideAngleCamera, .back, "Rueck-Weitwinkel"),
            (.builtInUltraWideCamera, .back, "Rueck-Ultraweit"),
            (.builtInTelephotoCamera, .back, "Rueck-Tele"),
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
        sessionQueue.async { [self] in
            do {
                session.beginConfiguration()
                session.sessionPreset = .inputPriority   // format is chosen manually below

                if let old = currentInput { session.removeInput(old) }
                let input = try AVCaptureDeviceInput(device: cam.device)
                guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
                session.addInput(input)
                currentInput = input

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

                let chosen = try configureDevice(cam.device, params)
                activeFormat = chosen

                if let c = videoOutput.connection(with: .video) {
                    // Landscape-right: the sensor's native orientation on iPhone
                    // already matches, so 0 degrees. Kept explicit so a future
                    // portrait mode has an obvious hook.
                    if #available(iOS 17.0, *), c.isVideoRotationAngleSupported(0) {
                        c.videoRotationAngle = 0
                    }
                    c.isVideoMirrored = false
                }

                session.commitConfiguration()
                session.startRunning()
                completion(.success(()))
            } catch {
                session.commitConfiguration()
                completion(.failure(error))
            }
        }
    }

    public func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            activeFormat = nil
        }
    }

    /// Picks the format whose dimensions and frame-rate range are nearest to the
    /// request, then locks the frame duration to the requested fps.
    private func configureDevice(_ device: AVCaptureDevice,
                                 _ p: StartParams) throws -> (UInt16, UInt16, UInt16) {
        let wantW = Int32(p.width), wantH = Int32(p.height), wantFps = Double(p.fps)

        func score(_ f: AVCaptureDevice.Format) -> Double {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            // Prefer NV12 video-range so no pixel conversion is needed.
            let subPenalty = sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 0.0 : 1_000_000.0
            let pixelDelta = abs(Double(d.width - wantW)) + abs(Double(d.height - wantH))
            let fpsDelta: Double = f.videoSupportedFrameRateRanges.map {
                if wantFps < $0.minFrameRate { return $0.minFrameRate - wantFps }
                if wantFps > $0.maxFrameRate { return wantFps - $0.maxFrameRate }
                return 0
            }.min() ?? 1000
            return pixelDelta + fpsDelta * 100 + subPenalty
        }

        guard let best = device.formats.min(by: { score($0) < score($1) }) else {
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
        return (UInt16(clamping: Int(d.width)), UInt16(clamping: Int(d.height)),
                UInt16(clamping: Int(fps.rounded())))
    }
}

extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
    }
}
