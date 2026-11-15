import AppKit

/// A small draggable snowman that lives on the desktop. Its eyes follow the
/// cursor and it wobbles when clicked.
final class SnowmanView: NSView {
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var dragged = false
    private var wobbleStart: TimeInterval = -10
    private var timer: Timer?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        let dx = m.x - dragStartMouse.x, dy = m.y - dragStartMouse.y
        if abs(dx) + abs(dy) > 3 { dragged = true }
        window?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragged, let o = window?.frame.origin {
            UserDefaults.standard.set(Double(o.x), forKey: "snowmanX")
            UserDefaults.standard.set(Double(o.y), forKey: "snowmanY")
        } else {
            wobbleStart = ProcessInfo.processInfo.systemUptime
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let cx = w / 2

        // Damped wobble around the base after a click.
        let age = ProcessInfo.processInfo.systemUptime - wobbleStart
        if age >= 0, age < 1.2 {
            let angle = 0.22 * exp(-3.2 * age) * sin(age * 16)
            ctx.translateBy(x: cx, y: 8)
            ctx.rotate(by: CGFloat(angle))
            ctx.translateBy(x: -cx, y: -8)
        }

        // Ground shadow
        NSColor(calibratedWhite: 0, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 40, y: 2, width: 80, height: 12)).fill()

        // Stick arms
        NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.14, alpha: 1).setStroke()
        let arms = NSBezierPath()
        arms.lineWidth = 3
        arms.lineCapStyle = .round
        arms.move(to: NSPoint(x: cx - 22, y: 78)); arms.line(to: NSPoint(x: cx - 52, y: 100))
        arms.move(to: NSPoint(x: cx - 44, y: 94)); arms.line(to: NSPoint(x: cx - 50, y: 84))
        arms.move(to: NSPoint(x: cx + 22, y: 78)); arms.line(to: NSPoint(x: cx + 52, y: 104))
        arms.move(to: NSPoint(x: cx + 44, y: 97)); arms.line(to: NSPoint(x: cx + 54, y: 92))
        arms.stroke()

        // Body: three snowballs
        ball(center: NSPoint(x: cx, y: 40), radius: 34)
        ball(center: NSPoint(x: cx, y: 84), radius: 25)
        let head = NSPoint(x: cx, y: 120)
        ball(center: head, radius: 18)

        // Scarf
        NSColor(calibratedRed: 0.85, green: 0.16, blue: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: cx - 19, y: 100, width: 38, height: 8),
                     xRadius: 4, yRadius: 4).fill()
        NSBezierPath(roundedRect: NSRect(x: cx + 6, y: 82, width: 9, height: 22),
                     xRadius: 3, yRadius: 3).fill()

        // Buttons
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        for y in [70.0, 84.0, 50.0] {
            NSBezierPath(ovalIn: NSRect(x: cx - 2.5, y: CGFloat(y), width: 5, height: 5)).fill()
        }

        // Eyes that follow the cursor
        var look = CGVector(dx: 0, dy: 0)
        if let win = window {
            let m = NSEvent.mouseLocation
            let hx = win.frame.minX + head.x, hy = win.frame.minY + head.y
            let dx = m.x - hx, dy = m.y - hy
            let d = max(1, sqrt(dx * dx + dy * dy))
            let k = min(1, d / 60) * 2.2
            look = CGVector(dx: dx / d * k, dy: dy / d * k)
        }
        for side in [-1.0, 1.0] {
            let ex = head.x + CGFloat(side) * 7, ey = head.y + 4
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: ex - 4.5, y: ey - 4.5, width: 9, height: 9)).fill()
            NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: ex - 2.5 + look.dx, y: ey - 2.5 + look.dy,
                                        width: 5, height: 5)).fill()
        }

        // Carrot nose
        NSColor(calibratedRed: 1, green: 0.5, blue: 0.1, alpha: 1).setFill()
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: head.x - 1, y: head.y + 1))
        nose.line(to: NSPoint(x: head.x + 16, y: head.y - 3))
        nose.line(to: NSPoint(x: head.x - 1, y: head.y - 5))
        nose.close()
        nose.fill()

        // Smile
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        for i in 0..<5 {
            let a = CGFloat.pi * (1.2 + 0.15 * CGFloat(i))
            let p = NSPoint(x: head.x + cos(a) * 10, y: head.y + sin(a) * 10 + 1)
            NSBezierPath(ovalIn: NSRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)).fill()
        }

        // Hat
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: head.x - 20, y: head.y + 13, width: 40, height: 5),
                     xRadius: 2.5, yRadius: 2.5).fill()
        NSBezierPath(roundedRect: NSRect(x: head.x - 12, y: head.y + 16, width: 24, height: 20),
                     xRadius: 2, yRadius: 2).fill()
        NSColor(calibratedRed: 0.85, green: 0.16, blue: 0.2, alpha: 1).setFill()
        NSRect(x: head.x - 12, y: head.y + 18, width: 24, height: 4).fill()
    }

    private func ball(center: NSPoint, radius: CGFloat) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)
        let gradient = NSGradient(starting: .white,
                                  ending: NSColor(calibratedRed: 0.8, green: 0.87, blue: 0.95, alpha: 1))
        gradient?.draw(in: path, relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
        NSColor(calibratedRed: 0.62, green: 0.72, blue: 0.84, alpha: 0.9).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class SnowmanController {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 130, height: 166)

    func setVisible(_ visible: Bool) {
        if visible { show() } else { panel?.orderOut(nil) }
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.hidesOnDeactivate = false
            p.isFloatingPanel = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = SnowmanView(frame: NSRect(origin: .zero, size: panelSize))
            p.setFrameOrigin(initialOrigin())
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    private func initialOrigin() -> NSPoint {
        let d = UserDefaults.standard
        if d.object(forKey: "snowmanX") != nil {
            let saved = NSPoint(x: d.double(forKey: "snowmanX"), y: d.double(forKey: "snowmanY"))
            let rect = NSRect(origin: saved, size: panelSize)
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return saved }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - panelSize.width - 60, y: vf.minY)
    }
}
