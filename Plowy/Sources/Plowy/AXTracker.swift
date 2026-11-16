import AppKit
import ApplicationServices

/// Reads the on-screen frames of Dock tiles and desktop icons through the
/// Accessibility API. Needs the user's Accessibility permission; without it
/// the lists simply stay empty.
final class AXTracker {
    static let shared = AXTracker()

    private let queue = DispatchQueue(label: "plowy.ax", qos: .utility)
    private let lock = NSLock()
    private var dock: [CGRect] = []
    private var icons: [CGRect] = []
    private var busy = false
    private var lastRefresh: TimeInterval = -10

    var trusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Frames in global Cocoa coordinates.
    func items() -> (dock: [CGRect], icons: [CGRect]) {
        lock.lock(); defer { lock.unlock() }
        return (dock, icons)
    }

    func refreshIfNeeded(now: TimeInterval) {
        guard now - lastRefresh > 1.5 || now < lastRefresh else { return }
        lastRefresh = now
        guard Settings.shared.iconSnow, trusted,
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            lock.lock(); dock = []; icons = []; lock.unlock()
            return
        }
        lock.lock()
        let wasBusy = busy
        busy = true
        lock.unlock()
        if wasBusy { return }

        queue.async { [self] in
            let d = fetchDock().map { flip($0, primaryHeight) }
            let i = fetchDesktopIcons().map { flip($0, primaryHeight) }
            lock.lock()
            dock = d
            icons = i
            busy = false
            lock.unlock()
        }
    }

    private func flip(_ r: CGRect, _ primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: AX helpers

    private func app(_ bundleID: String) -> AXUIElement? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.processIdentifier else { return nil }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.4)
        return el
    }

    private func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    private func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private func role(_ el: AXUIElement) -> String {
        (attr(el, kAXRoleAttribute as String) as? String) ?? ""
    }

    private func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute as String),
              let s = attr(el, kAXSizeAttribute as String),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    // MARK: Fetching (top-left origin coordinates)

    private func fetchDock() -> [CGRect] {
        guard let dockApp = app("com.apple.dock") else { return [] }
        var out: [CGRect] = []
        for list in children(dockApp) {
            for item in children(list) where role(item) == "AXDockItem" {
                guard let f = frame(item), f.width >= 24, f.height >= 24 else { continue }
                let ratio = f.width / f.height
                if ratio > 0.6 && ratio < 1.7 { out.append(f) }
            }
        }
        return out
    }

    private func fetchDesktopIcons() -> [CGRect] {
        guard let finder = app("com.apple.finder") else { return [] }
        var out: [CGRect] = []
        var visited = 0
        // The desktop is a scroll area directly under the application
        // (not inside a window); its icons are AXImage elements.
        var level: [AXUIElement] = children(finder).filter {
            let r = role($0)
            return r != "AXWindow" && r != "AXMenuBar"
        }
        for _ in 0..<4 {
            var next: [AXUIElement] = []
            for el in level {
                visited += 1
                if visited > 700 { return out }
                if role(el) == "AXImage" {
                    if let f = frame(el), f.width >= 24, f.height >= 24,
                       f.width <= 400, f.height <= 400 { out.append(f) }
                } else {
                    next.append(contentsOf: children(el))
                }
            }
            level = next
            if level.isEmpty { break }
        }
        return out
    }
}
