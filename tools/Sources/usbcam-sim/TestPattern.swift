import CoreGraphics
import CoreImage
import CoreText
import CoreVideo
import Foundation

/// Renders a moving test pattern into NV12 video-range BT.709 pixel buffers.
///
/// Drawing happens in an RGB bitmap context (CoreGraphics/CoreText), the result is
/// converted into a pooled NV12 buffer by CoreImage. The pattern carries colour bars,
/// a box that travels across the frame and a large timestamp, so a receiver can check
/// motion and latency by eye.
final class TestPatternRenderer {
    let width: Int
    let height: Int

    private let pool: CVPixelBufferPool
    private let ciContext: CIContext
    private let bitmap: CGContext
    private let rgbSpace: CGColorSpace
    private let font: CTFont
    private let labelFont: CTFont

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        self.rgbSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()

        let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 4]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary,
                                             bufferAttrs as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw SimError.setupFailed("CVPixelBufferPoolCreate failed: \(status)")
        }
        self.pool = pool

        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: rgbSpace,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw SimError.setupFailed("CGContext creation failed")
        }
        self.bitmap = bitmap
        self.ciContext = CIContext(options: [.workingColorSpace: rgbSpace, .useSoftwareRenderer: false])
        self.font = CTFontCreateWithName("Menlo-Bold" as CFString, CGFloat(height) / 10.0, nil)
        self.labelFont = CTFontCreateWithName("Menlo" as CFString, CGFloat(height) / 24.0, nil)
    }

    /// Draws frame `index` (pts in microseconds) and returns a pooled NV12 buffer.
    func render(frameIndex: Int, ptsUs: UInt64) throws -> CVPixelBuffer {
        draw(frameIndex: frameIndex, ptsUs: ptsUs)

        guard let image = bitmap.makeImage() else {
            throw SimError.setupFailed("CGBitmapContext.makeImage failed")
        }

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw SimError.setupFailed("CVPixelBufferPoolCreatePixelBuffer failed: \(status)")
        }
        Self.tagBT709(buffer)

        ciContext.render(CIImage(cgImage: image), to: buffer,
                         bounds: CGRect(x: 0, y: 0, width: width, height: height),
                         colorSpace: rgbSpace)
        return buffer
    }

    /// The colour convention is fixed by the spec: BT.709 primaries, transfer and matrix.
    static func tagBT709(_ buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }

    // MARK: - Drawing

    private static let bars: [CGColor] = [
        CGColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),
        CGColor(red: 0.75, green: 0.75, blue: 0.00, alpha: 1),
        CGColor(red: 0.00, green: 0.75, blue: 0.75, alpha: 1),
        CGColor(red: 0.00, green: 0.75, blue: 0.00, alpha: 1),
        CGColor(red: 0.75, green: 0.00, blue: 0.75, alpha: 1),
        CGColor(red: 0.75, green: 0.00, blue: 0.00, alpha: 1),
        CGColor(red: 0.00, green: 0.00, blue: 0.75, alpha: 1),
        CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
    ]

    private func draw(frameIndex: Int, ptsUs: UInt64) {
        let w = CGFloat(width), h = CGFloat(height)
        bitmap.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Colour bars across the top two thirds.
        let barWidth = w / CGFloat(Self.bars.count)
        for (i, colour) in Self.bars.enumerated() {
            bitmap.setFillColor(colour)
            bitmap.fill(CGRect(x: CGFloat(i) * barWidth, y: h / 3, width: barWidth, height: h * 2 / 3))
        }

        // A box travelling left to right and bouncing, so motion is obvious and the
        // encoder gets real inter-frame change to work with.
        let boxSize = h / 8
        let travel = w - boxSize
        let phase = CGFloat((frameIndex % 240)) / 240.0
        let x = phase < 0.5 ? travel * (phase * 2) : travel * (2 - phase * 2)
        let y = h / 3 + (h * 2 / 3 - boxSize) * (0.5 + 0.45 * sin(CGFloat(frameIndex) / 17.0))
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: x, y: y, width: boxSize, height: boxSize))
        bitmap.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        bitmap.fill(CGRect(x: x + boxSize * 0.2, y: y + boxSize * 0.2,
                           width: boxSize * 0.6, height: boxSize * 0.6))

        // Big timestamp plus frame counter in the bottom third.
        let seconds = Double(ptsUs) / 1_000_000.0
        drawText(String(format: "%09.3f", seconds), font: font, at: CGPoint(x: w * 0.03, y: h * 0.14))
        drawText("frame \(frameIndex)  \(width)x\(height)", font: labelFont,
                 at: CGPoint(x: w * 0.03, y: h * 0.04))
    }

    private func drawText(_ text: String, font: CTFont, at point: CGPoint) {
        // CoreText attribute keys directly — AppKit is not linked here.
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString,
                                                  attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        bitmap.textPosition = point
        CTLineDraw(line, bitmap)
    }
}
