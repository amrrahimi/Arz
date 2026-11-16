import AppKit
import ImageIO
import Vision

/// Finds the main subject of the desktop picture (for example a car) so snow
/// can settle on its upper outline. Experimental; needs macOS 14.
final class WallpaperAnalyzer {
    static let shared = WallpaperAnalyzer()

    private var results: [String: (url: URL, contour: [CGFloat])] = [:]
    private var pending = Set<String>()

    /// Main thread only. Returns the subject's top outline for the screen, one
    /// value per snow column in screen points from the bottom (`nan` = none).
    /// Returns nil while the picture is still being analysed.
    func contour(for screen: NSScreen) -> (url: URL, contour: [CGFloat])? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let key = NSStringFromRect(screen.frame)
        if let r = results[key], r.url == url { return r }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)

        let size = screen.frame.size
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let clipping = (options[.allowClipping] as? Bool) ?? true
        DispatchQueue.global(qos: .utility).async {
            var contour: [CGFloat] = []
            if #available(macOS 14.0, *) {
                contour = WallpaperAnalyzer.analyse(url: url, screenSize: size, fill: clipping)
            }
            DispatchQueue.main.async {
                self.results[key] = (url, contour)
                self.pending.remove(key)
            }
        }
        return nil
    }

    @available(macOS 14.0, *)
    private static func analyse(url: URL, screenSize: CGSize, fill: Bool) -> [CGFloat] {
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
        else { return [] }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let mask = try? observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler)
        else { return [] }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float,
              let baseAddress = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        guard w > 8, h > 8 else { return [] }

        func on(_ x: Int, _ y: Int) -> Bool {
            baseAddress.advanced(by: y * rowBytes)
                .assumingMemoryBound(to: Float32.self)[x] > 0.5
        }

        // How the picture is mapped onto the screen (centred, fill or fit).
        let sx = screenSize.width / CGFloat(w), sy = screenSize.height / CGFloat(h)
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let offsetX = (screenSize.width - CGFloat(w) * scale) / 2
        let offsetTop = (screenSize.height - CGFloat(h) * scale) / 2

        let columns = max(1, Int(ceil(screenSize.width / Pile.columnWidth)))
        var contour = [CGFloat](repeating: .nan, count: columns)
        var found = 0
        for c in 0..<columns {
            let screenX = (CGFloat(c) + 0.5) * Pile.columnWidth
            let ix = Int((screenX - offsetX) / scale)
            guard ix >= 0, ix < w else { continue }
            var iy = 0
            while iy < h - 4 {
                if on(ix, iy) && on(ix, iy + 1) && on(ix, iy + 2) && on(ix, iy + 3) { break }
                iy += 1
            }
            // Touching the top of the picture means it is not an upper surface.
            guard iy > 2, iy < h - 4 else { continue }
            let y = screenSize.height - offsetTop - CGFloat(iy) * scale
            guard y > 20, y < screenSize.height - 30 else { continue }
            contour[c] = y
            found += 1
        }
        return found >= 8 ? contour : []
    }
}
