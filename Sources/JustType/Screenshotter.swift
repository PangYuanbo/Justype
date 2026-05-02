import AppKit
import CoreGraphics

enum Screenshotter {
    /// Capture the primary display, downscale to fit `maxDimension`, and
    /// return JPEG data. Returns nil if Screen Recording permission has not
    /// been granted (macOS will surface its own prompt on first attempt).
    static func capturePrimary(maxDimension: CGFloat = 1280, quality: CGFloat = 0.6) -> Data? {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        return downscaleToJPEG(cgImage: cgImage, maxDimension: maxDimension, quality: quality)
    }

    private static func downscaleToJPEG(cgImage: CGImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = min(maxDimension / max(w, h), 1.0)
        let tw = max(1, Int(w * scale))
        let th = max(1, Int(h * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: tw, height: th,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))

        guard let scaled = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    static var hasPermission: Bool {
        if #available(macOS 11.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    @discardableResult
    static func requestPermissionIfNeeded() -> Bool {
        if #available(macOS 11.0, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
}
