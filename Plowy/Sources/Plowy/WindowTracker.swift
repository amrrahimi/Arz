import AppKit
import CoreGraphics

struct WindowInfo {
    let id: CGWindowID
    /// Global Cocoa coordinates (origin bottom-left, y up).
    let frame: CGRect
}

/// A horizontal edge where snow can settle.
struct Surface {
    enum Kind { case window, icon, dock }
    let key: String
    let kind: Kind
    /// Global Cocoa coordinates; snow sits on `frame.maxY`.
    let frame: CGRect
    /// Parts of the top edge (global x ranges) not covered by windows in front.
    let segments: [ClosedRange<CGFloat>]
}

struct Snapshot {
    var version = 0
    /// Front-to-back.
    var windows: [WindowInfo] = []
    var surfaces: [Surface] = []
    var dock: [CGRect] = []
}

/// Polls the window server for window frames. Only geometry is read, so no
/// Screen Recording permission is needed.
final class WindowTracker {
    static let shared = WindowTracker()

    private var cached = Snapshot()
    private var lastRefresh: TimeInterval = -1
    private let interval: TimeInterval = 0.15
    private let ownPID = getpid()

    func snapshot(now: TimeInterval) -> Snapshot {
        if now - lastRefresh >= interval || now < lastRefresh {
            lastRefresh = now
            let version = cached.version + 1
            cached = compute()
            cached.version = version
            AXTracker.shared.refreshIfNeeded(now: now)
        }
        return cached
    }

    private func compute() -> Snapshot {
        var snap = Snapshot()
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return snap }

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            if b.width < 80 || b.height < 40 { continue }
            // CG uses a top-left origin; flip into Cocoa coordinates.
            let frame = CGRect(x: b.minX, y: primaryHeight - b.maxY,
                               width: b.width, height: b.height)
            snap.windows.append(WindowInfo(id: CGWindowID(number), frame: frame))
        }

        for (i, w) in snap.windows.enumerated() {
            let segs = visibleSegments(of: w.frame, occluders: snap.windows[0..<i])
            if !segs.isEmpty {
                snap.surfaces.append(Surface(key: "w\(w.id)", kind: .window,
                                             frame: w.frame, segments: segs))
            }
        }

        guard Settings.shared.iconSnow else { return snap }
        let ax = AXTracker.shared.items()

        // Desktop icons sit behind every window.
        for r in ax.icons {
            let side = min(r.width, r.height)
            let f = CGRect(x: r.midX - side * 0.4, y: r.minY,
                           width: side * 0.8, height: r.height - side * 0.11)
            let segs = visibleSegments(of: f, occluders: snap.windows[...])
            if !segs.isEmpty {
                snap.surfaces.append(Surface(key: "i\(Int(r.minX)):\(Int(r.maxY))", kind: .icon,
                                             frame: f, segments: segs))
            }
        }
        // The Dock floats above windows.
        for r in ax.dock {
            // A Dock tile is taller and wider than the icon drawn inside it.
            let f = CGRect(x: r.minX + r.width * 0.12, y: r.minY,
                           width: r.width * 0.76, height: r.height * 0.78)
            snap.surfaces.append(Surface(key: "d\(Int(r.minX)):\(Int(r.width))", kind: .dock,
                                         frame: f, segments: [f.minX...f.maxX]))
        }
        snap.dock = ax.dock
        return snap
    }

    private func visibleSegments(of frame: CGRect,
                                 occluders: ArraySlice<WindowInfo>) -> [ClosedRange<CGFloat>] {
        let top = frame.maxY
        var segs: [ClosedRange<CGFloat>] = [frame.minX...frame.maxX]
        for o in occluders {
            guard o.frame.minY <= top, o.frame.maxY > top else { continue }
            segs = subtract(segs, o.frame.minX, o.frame.maxX)
            if segs.isEmpty { break }
        }
        return segs.filter { $0.upperBound - $0.lowerBound >= 12 }
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
