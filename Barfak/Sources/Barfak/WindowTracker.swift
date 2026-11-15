import AppKit
import CoreGraphics

/// The top edge of an on-screen window where snow can settle.
struct Surface {
    let windowID: CGWindowID
    /// Window frame in global Cocoa coordinates (origin bottom-left, y up).
    let frame: CGRect
    /// Parts of the top edge (global x ranges) not covered by windows in front.
    let segments: [ClosedRange<CGFloat>]
}

/// Polls the window server for window frames. Only geometry is read, so no
/// Screen Recording permission is needed.
final class WindowTracker {
    static let shared = WindowTracker()

    private var cached: [Surface] = []
    private var lastRefresh: TimeInterval = -1
    private let interval: TimeInterval = 0.35
    private let ownPID = getpid()

    func surfaces(now: TimeInterval) -> [Surface] {
        if now - lastRefresh >= interval || now < lastRefresh {
            lastRefresh = now
            cached = compute()
        }
        return cached
    }

    private func compute() -> [Surface] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        // Front-to-back list of normal application windows.
        var windows: [(id: CGWindowID, frame: CGRect)] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            if b.width < 80 || b.height < 40 { continue }
            // CG uses top-left origin; flip into Cocoa coordinates.
            let frame = CGRect(x: b.minX, y: primaryHeight - b.maxY,
                               width: b.width, height: b.height)
            windows.append((CGWindowID(number), frame))
        }

        var result: [Surface] = []
        for (i, w) in windows.enumerated() {
            let top = w.frame.maxY
            var segs: [ClosedRange<CGFloat>] = [w.frame.minX...w.frame.maxX]
            for j in 0..<i {
                let o = windows[j].frame
                guard o.minY <= top, o.maxY > top else { continue }
                segs = subtract(segs, o.minX, o.maxX)
                if segs.isEmpty { break }
            }
            segs = segs.filter { $0.upperBound - $0.lowerBound >= 12 }
            if !segs.isEmpty {
                result.append(Surface(windowID: w.id, frame: w.frame, segments: segs))
            }
        }
        return result
    }

    private func subtract(_ segs: [ClosedRange<CGFloat>],
                          _ a: CGFloat, _ b: CGFloat) -> [ClosedRange<CGFloat>] {
        var out: [ClosedRange<CGFloat>] = []
        for s in segs {
            if b <= s.lowerBound || a >= s.upperBound { out.append(s); continue }
            if a > s.lowerBound { out.append(s.lowerBound...a) }
            if b < s.upperBound { out.append(b...s.upperBound) }
        }
        return out
    }
}
