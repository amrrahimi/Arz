import AppKit
import SpriteKit

/// The snow simulation for a single screen.
final class SnowScene: SKScene {
    private let screen: NSScreen
    /// Screen frame in global Cocoa coordinates.
    private let screenFrame: CGRect
    private let art = Art.shared

    // Snow
    private var flakes: [Flake] = []
    private var debris: [Flake] = []
    private var piles: [String: Pile] = [:]
    private var ground: Pile?
    private var wallpaper: Pile?
    private var wallpaperURL: URL?
    private var lastWallpaperCheck: TimeInterval = -100

    // Decorations
    private var garlands: [String: Garland] = [:]
    private var snapshot = Snapshot()
    private var syncedVersion = -1
    private var settingsDirty = true

    // Loader
    private var plow: SKSpriteNode?
    private var plowX: CGFloat = 0
    private var plowDirection: CGFloat = 1
    private var plowCooldown: TimeInterval = 0
    private var groundFill: CGFloat = 0

    // Snowballs
    private var balls: [Snowball] = []

    // Cable cars
    private let station = SKSpriteNode(texture: Art.shared.station)
    private let ropePreview = SKShapeNode()
    private var cables: [Cable] = []

    // Mouse
    private enum Drag {
        case none
        case rolling(Snowball, lastX: CGFloat)
        case ball(Snowball, offset: CGPoint)
        case cable(from: CGPoint)
    }
    private var drag = Drag.none
    private var lastMouse = CGPoint(x: -1000, y: -1000)
    private var capturing = false

    private var lastTime: TimeInterval = 0
    private var startTime: TimeInterval = -1
    private var lastPathRebuild: TimeInterval = 0
    private var demoDone = false

    init(screen: NSScreen) {
        self.screen = screen
        self.screenFrame = screen.frame
        super.init(size: screen.frame.size)
        scaleMode = .resizeFill
        backgroundColor = .clear

        station.size = Art.stationSize
        station.zPosition = 30
        addChild(station)
        ropePreview.strokeColor = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 0.9)
        ropePreview.fillColor = .clear
        ropePreview.lineWidth = 1.6
        ropePreview.zPosition = 29
        addChild(ropePreview)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: Settings.didChange, object: nil)
        center.addObserver(self, selector: #selector(plowRequested),
                           name: .barfakPlowNow, object: nil)
        center.addObserver(self, selector: #selector(clearCables),
                           name: .barfakClearCables, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func settingsChanged() { settingsDirty = true }
    @objc private func plowRequested() { startPlow() }
    @objc private func clearCables() {
        cables.forEach { $0.node.removeFromParent() }
        cables.removeAll()
    }

    private var stationPoint: CGPoint {
        CGPoint(x: size.width / 2, y: screen.visibleFrame.maxY - screenFrame.minY - 24)
    }

    // MARK: Flakes

    private var targetFlakeCount: Int {
        let base = [110, 260, 520][Settings.shared.intensity]
        let area = (size.width * size.height) / (1440 * 900)
        return Int(CGFloat(base) * min(2.2, max(0.6, area)))
    }

    private func configure(_ f: Flake, anywhere: Bool) {
        f.size = CGFloat.random(in: 2...7.5)
        f.lands = f.size > 3.6
        f.vy = 26 + f.size * 13 + CGFloat.random(in: 0...18)
        f.phase = CGFloat.random(in: 0...(2 * .pi))
        f.sway = CGFloat.random(in: 6...22)
        f.x = CGFloat.random(in: -60...(size.width + 60))
        f.y = anywhere ? CGFloat.random(in: 0...size.height)
                       : size.height + CGFloat.random(in: 5...60)
        f.node.size = CGSize(width: f.size, height: f.size)
        f.node.alpha = 0.4 + 0.55 * (f.size / 7.5)
        f.node.zPosition = f.size
    }

    private func adjustFlakeCount() {
        let target = targetFlakeCount
        var changed = 0
        while flakes.count < target && changed < 12 {
            let f = Flake(texture: art.flake)
            configure(f, anywhere: flakes.count < target / 3)
            addChild(f.node)
            flakes.append(f)
            changed += 1
        }
        while flakes.count > target && changed < 12 {
            flakes.removeLast().node.removeFromParent()
            changed += 1
        }
    }

    private func spawnDebris(x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat? = nil) {
        guard debris.count < 600 else { return }
        let f = Flake(texture: art.flake)
        f.size = CGFloat.random(in: 3...6)
        f.vx = vx
        f.vy = vy ?? CGFloat.random(in: 10...60)
        f.phase = CGFloat.random(in: 0...(2 * .pi))
        f.sway = CGFloat.random(in: 10...40)
        f.x = x
        f.y = y
        f.node.size = CGSize(width: f.size, height: f.size)
        f.node.alpha = 0.9
        f.node.zPosition = 9
        addChild(f.node)
        debris.append(f)
    }

    // MARK: Piles and garlands

    private func dump(_ pile: Pile) {
        var i = 0
        while i < pile.heights.count {
            let h = pile.heights[i]
            let x = pile.columnX(i)
            if h > 2, pile.covers(x) {
                spawnDebris(x: x, y: pile.y + pile.base[i] + CGFloat.random(in: 0...h))
            }
            i += 2
        }
    }

    private func remove(_ pile: Pile?) {
        guard let pile = pile else { return }
        dump(pile)
        pile.node.removeFromParent()
    }

    private func groundSegments() -> [ClosedRange<CGFloat>] {
        // Leave the Dock's strip free: its icons get their own snow.
        var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
        for r in snapshot.dock where r.intersects(screenFrame) && r.minY - screenFrame.minY < 40 {
            lo = min(lo, r.minX - screenFrame.minX - 12)
            hi = max(hi, r.maxX - screenFrame.minX + 12)
        }
        guard lo < hi else { return [0...size.width] }
        var segs: [ClosedRange<CGFloat>] = []
        if lo > 12 { segs.append(0...lo) }
        if hi < size.width - 12 { segs.append(hi...size.width) }
        return segs
    }

    private func syncSurfaces() {
        let s = Settings.shared

        if s.accumulate {
            if ground == nil {
                let g = Pile(key: "ground",
                             globalFrame: CGRect(x: 0, y: 0, width: size.width, height: 0),
                             x0: 0, y: 0,
                             cap: Pile.noisyCaps(width: size.width, low: 5, high: 30))
                addChild(g.node)
                ground = g
            }
            let segs = groundSegments()
            if let g = ground, g.segments != segs {
                g.segments = segs
                g.dirty = true
            }
        } else {
            remove(ground)
            ground = nil
        }

        var seenPiles = Set<String>()
        var seenGarlands = Set<String>()
        for sf in snapshot.surfaces {
            let ly = sf.frame.maxY - screenFrame.minY
            guard ly > 16, ly < size.height - 4 else { continue }
            var segs: [ClosedRange<CGFloat>] = []
            for g in sf.segments {
                let a = max(0, g.lowerBound - screenFrame.minX)
                let b = min(size.width, g.upperBound - screenFrame.minX)
                if b - a >= 12 { segs.append(a...b) }
            }
            guard !segs.isEmpty else { continue }

            if s.lights && sf.kind == .window {
                seenGarlands.insert(sf.key)
                let garland: Garland
                if let existing = garlands[sf.key] {
                    garland = existing
                } else {
                    garland = Garland()
                    addChild(garland.node)
                    garlands[sf.key] = garland
                }
                garland.update(segments: segs, y: ly, style: s.lightStyle)
            }

            guard s.accumulate else { continue }
            seenPiles.insert(sf.key)
            if let pile = piles[sf.key] {
                let old = pile.globalFrame
                if abs(old.width - sf.frame.width) > 0.5 {
                    remove(pile)
                    piles[sf.key] = nil
                } else {
                    if abs(old.minX - sf.frame.minX) > 0.5 || abs(old.maxY - sf.frame.maxY) > 0.5 {
                        // The window was dragged: the snow falls off.
                        dump(pile)
                        for i in pile.heights.indices { pile.heights[i] = 0 }
                        pile.globalFrame = sf.frame
                        pile.x0 = sf.frame.minX - screenFrame.minX
                        pile.y = ly
                        pile.dirty = true
                    }
                    if pile.segments != segs {
                        pile.segments = segs
                        pile.dirty = true
                    }
                    continue
                }
            }
            let high: CGFloat = sf.kind == .window ? 15 : 8
            let pile = Pile(key: sf.key, globalFrame: sf.frame,
                            x0: sf.frame.minX - screenFrame.minX, y: ly,
                            cap: Pile.noisyCaps(width: sf.frame.width, low: high * 0.45, high: high))
            pile.segments = segs
            addChild(pile.node)
            piles[sf.key] = pile
        }
        for key in Array(piles.keys) where !seenPiles.contains(key) {
            remove(piles[key])
            piles[key] = nil
        }
        for key in Array(garlands.keys) where !seenGarlands.contains(key) {
            garlands[key]?.node.removeFromParent()
            garlands[key] = nil
        }

        updateWallpaperSegments()
    }

    // MARK: Wallpaper snow (experimental)

    private func checkWallpaper(now: TimeInterval) {
        guard now - lastWallpaperCheck > 3 || now < lastWallpaperCheck else { return }
        lastWallpaperCheck = now
        let s = Settings.shared
        guard s.wallpaperSnow, s.accumulate else {
            remove(wallpaper)
            wallpaper = nil
            wallpaperURL = nil
            return
        }
        guard let result = WallpaperAnalyzer.shared.contour(for: screen),
              result.url != wallpaperURL else { return }
        wallpaperURL = result.url
        remove(wallpaper)
        wallpaper = nil

        let contour = result.contour
        let n = contour.count
        guard n > 4 else { return }
        var base = [CGFloat](repeating: 0, count: n)
        var cap = [CGFloat](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            let c = contour[i], l = contour[i - 1], r = contour[i + 1]
            guard !c.isNaN, !l.isNaN, !r.isNaN else { continue }
            // Snow slides off steep parts of the outline.
            let slope = abs(r - l) / (2 * Pile.columnWidth)
            let room = 7.5 - slope * 3.5 + CGFloat.random(in: -0.8...0.8)
            if room >= 1.5 {
                cap[i] = room
                base[i] = c
            }
        }
        let pile = Pile(key: "wallpaper", globalFrame: screenFrame, x0: 0, y: 0, cap: cap, base: base)
        pile.node.zPosition = 9
        addChild(pile.node)
        wallpaper = pile
        updateWallpaperSegments()
    }

    /// Snow on the picture only shows where the desktop itself is visible.
    private func updateWallpaperSegments() {
        guard let wp = wallpaper else { return }
        let cw = Pile.columnWidth
        var segs: [ClosedRange<CGFloat>] = []
        var runStart: CGFloat?
        for i in 0...wp.heights.count {
            var ok = i < wp.heights.count && wp.cap[i] > 0
            if ok {
                let point = CGPoint(x: screenFrame.minX + wp.columnX(i),
                                    y: screenFrame.minY + wp.base[i] + 1)
                for w in snapshot.windows where w.frame.contains(point) { ok = false; break }
            }
            let x = CGFloat(i) * cw
            if ok {
                if runStart == nil { runStart = x }
            } else if let start = runStart {
                if x - start >= 9 { segs.append(start...x) }
                runStart = nil
            }
        }
        if wp.segments != segs {
            wp.segments = segs
            wp.dirty = true
        }
    }

    // MARK: Loader

    private func startPlow() {
        guard plow == nil, ground != nil else { return }
        let node = SKSpriteNode(texture: art.loader)
        node.size = Art.loaderSize
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.zPosition = 25
        plowDirection = -plowDirection
        plowX = plowDirection > 0 ? -110 : size.width + 110
        node.xScale = plowDirection
        addChild(node)
        plow = node
    }

    private func updatePlow(dt: CGFloat, time: CGFloat, now: TimeInterval) {
        guard let node = plow else {
            if Settings.shared.plow, groundFill > 0.88, now > plowCooldown { startPlow() }
            return
        }
        let before = plowX + plowDirection * 80
        plowX += plowDirection * 105 * dt
        let after = plowX + plowDirection * 80
        node.position = CGPoint(x: plowX, y: abs(sin(time * 17)) * 0.9)

        if let g = ground {
            let a = g.index(at: min(before, after)), b = g.index(at: max(before, after))
            if a <= b, max(before, after) >= 0, min(before, after) <= size.width {
                for i in a...b where g.heights[i] > 0.3 {
                    if Int.random(in: 0..<2) == 0 {
                        spawnDebris(x: g.columnX(i) + plowDirection * 6,
                                    y: g.heights[i] + CGFloat.random(in: 4...18),
                                    vx: plowDirection * CGFloat.random(in: 40...150),
                                    vy: -CGFloat.random(in: 60...190))
                    }
                    g.heights[i] = 0
                    g.dirty = true
                }
            }
        }
        if plowX < -130 || plowX > size.width + 130 {
            node.removeFromParent()
            plow = nil
            plowCooldown = now + 20
        }
    }

    // MARK: Snowballs

    @discardableResult
    private func addBall(x: CGFloat, y: CGFloat, r: CGFloat) -> Snowball {
        let ball = Snowball(x: x, y: y, r: r)
        addChild(ball.node)
        balls.append(ball)
        if balls.count > 14 {
            balls.removeFirst().node.removeFromParent()
        }
        return ball
    }

    private func ball(at p: CGPoint) -> Snowball? {
        for b in balls.reversed() where hypot(p.x - b.x, p.y - b.y) <= b.r + 3 { return b }
        return nil
    }

    private func updateBalls(dt: CGFloat) {
        var rolling: Snowball?
        if case .rolling(let b, _) = drag { rolling = b }

        for b in balls where !b.held && b !== rolling {
            b.vy -= 1400 * dt
            b.y += b.vy * dt
            var rest = b.r * 0.92
            var support: Snowball?
            for o in balls where o !== b && !o.held && o !== rolling && o.support !== b {
                guard abs(b.x - o.x) < o.r * 0.85, o.y < b.y + 1 else { continue }
                let top = o.y + (o.r + b.r) * 0.86
                if top > rest { rest = top; support = o }
            }
            if b.y <= rest {
                b.y = rest
                b.vy = 0
                b.support = support
                if let o = support { b.x += (o.x - b.x) * min(1, dt * 6) }
            } else {
                b.support = nil
            }
            b.x = min(size.width - b.r, max(b.r, b.x))
            b.sync()
        }

        // Three stacked balls become a snowman.
        func hasRider(_ b: Snowball) -> Bool { balls.contains { $0.support === b } }
        for b in balls {
            let rider = balls.first { $0.support === b }
            if rider == nil, let below = b.support, below.support != nil {
                b.setRole(.head)
            } else if let rider = rider, !hasRider(rider), b.support != nil {
                b.setRole(.torso)
            } else {
                b.setRole(.plain)
            }
        }
    }

    // MARK: Mouse

    /// True where the overlay should take clicks instead of passing them on.
    private func wantsMouse(at p: CGPoint) -> Bool {
        if case .none = drag {} else { return true }
        if Settings.shared.cableCar, hypot(p.x - stationPoint.x, p.y - stationPoint.y) < 20 { return true }
        if ball(at: p) != nil { return true }
        if let g = ground, g.covers(p.x), g.height(at: p.x) > 3, p.y <= g.top(at: p.x) + 3 { return true }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        if Settings.shared.cableCar, hypot(p.x - stationPoint.x, p.y - stationPoint.y) < 22 {
            drag = .cable(from: p)
        } else if let b = ball(at: p) {
            b.held = true
            b.support = nil
            drag = .ball(b, offset: CGPoint(x: b.x - p.x, y: b.y - p.y))
        } else if let g = ground, g.covers(p.x), g.height(at: p.x) > 2 {
            let b = addBall(x: p.x, y: 5, r: 5)
            drag = .rolling(b, lastX: p.x)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = event.location(in: self)
        switch drag {
        case .none:
            break
        case .cable:
            let path = CGMutablePath()
            path.move(to: stationPoint)
            path.addLine(to: p)
            ropePreview.path = path
        case .ball(let b, let offset):
            b.x = p.x + offset.x
            b.y = max(b.r * 0.92, p.y + offset.y)
            b.vy = 0
            b.sync()
        case .rolling(let b, let lastX):
            guard let g = ground else { break }
            let dx = p.x - lastX
            if abs(dx) >= 1 {
                // Pick up the snow the ball rolls over.
                var gathered: CGFloat = 0
                let a = g.index(at: min(lastX, p.x) - b.r * 0.5)
                let c = g.index(at: max(lastX, p.x) + b.r * 0.5)
                if a <= c {
                    for i in a...c where g.heights[i] > 0.4 && g.covers(g.columnX(i)) {
                        gathered += g.heights[i] * 0.85 * Pile.columnWidth
                        g.heights[i] *= 0.15
                        g.dirty = true
                    }
                }
                let area = CGFloat.pi * b.r * b.r + gathered * 2.2
                b.r = min(38, sqrt(area / .pi))
                b.node.zRotation -= dx / max(6, b.r)
                drag = .rolling(b, lastX: p.x)
            }
            b.x = min(size.width - b.r, max(b.r, p.x))
            b.y = b.r * 0.92
            b.sync()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = event.location(in: self)
        switch drag {
        case .none:
            break
        case .cable(let from):
            ropePreview.path = nil
            if hypot(p.x - from.x, p.y - from.y) > 30 {
                attachCable(to: p)
            } else if let last = cables.popLast() {
                // A plain click on the station removes the newest rope.
                last.node.removeFromParent()
            }
        case .ball(let b, _):
            b.held = false
        case .rolling(let b, _):
            if b.r < 7 {
                // Too small to keep: it crumbles.
                for _ in 0..<6 { spawnDebris(x: b.x + CGFloat.random(in: -6...6), y: b.y) }
                b.node.removeFromParent()
                balls.removeAll { $0 === b }
            }
        }
        drag = .none
    }

    // MARK: Cable cars

    private func attachCable(to p: CGPoint) {
        let global = CGPoint(x: p.x + screenFrame.minX, y: p.y + screenFrame.minY)
        var anchor = Cable.Anchor.fixed(p)
        for w in snapshot.windows where w.frame.contains(global) {
            anchor = .window(id: w.id, dx: global.x - w.frame.minX, dy: global.y - w.frame.maxY)
            break
        }
        let cable = Cable(anchor: anchor)
        addChild(cable.node)
        cables.append(cable)
        if cables.count > 6 {
            cables.removeFirst().node.removeFromParent()
        }
    }

    private func updateCables(dt: CGFloat) {
        station.isHidden = !Settings.shared.cableCar
        station.position = CGPoint(x: stationPoint.x, y: stationPoint.y + 5)
        guard Settings.shared.cableCar else {
            if !cables.isEmpty { clearCables() }
            return
        }
        var keep: [Cable] = []
        for cable in cables {
            var end: CGPoint?
            switch cable.anchor {
            case .fixed(let p):
                end = p
            case .window(let id, let dx, let dy):
                if let w = snapshot.windows.first(where: { $0.id == id }) {
                    end = CGPoint(x: w.frame.minX + dx - screenFrame.minX,
                                  y: w.frame.maxY + dy - screenFrame.minY)
                }
            }
            if let end = end {
                cable.update(start: stationPoint, end: end, dt: dt)
                keep.append(cable)
            } else {
                // Its window was closed.
                cable.node.removeFromParent()
            }
        }
        cables = keep
    }

    // MARK: Demo (automated screenshots)

    private func runDemo() {
        demoDone = true
        var all = Array(piles.values)
        if let g = ground { all.append(g) }
        if let w = wallpaper { all.append(w) }
        for p in all {
            for i in p.heights.indices { p.heights[i] = p.cap[i] * CGFloat.random(in: 0.9...1) }
            p.dirty = true
        }
        attachCable(to: CGPoint(x: size.width * 0.22, y: size.height * 0.5))
        if let w = snapshot.windows.first {
            attachCable(to: CGPoint(x: w.frame.maxX - 30 - screenFrame.minX,
                                    y: w.frame.maxY - 4 - screenFrame.minY))
        }
        addBall(x: size.width * 0.8, y: 40, r: 30)
        addBall(x: size.width * 0.8, y: 160, r: 22)
        addBall(x: size.width * 0.8, y: 280, r: 15)
        addBall(x: size.width * 0.68, y: 40, r: 18)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        if startTime < 0 { startTime = currentTime }
        let dt = CGFloat(min(1.0 / 30.0, max(0, currentTime - lastTime)))
        lastTime = currentTime
        guard dt > 0 else { return }
        let s = Settings.shared

        adjustFlakeCount()

        snapshot = WindowTracker.shared.snapshot(now: currentTime)
        if snapshot.version != syncedVersion || settingsDirty {
            syncedVersion = snapshot.version
            settingsDirty = false
            syncSurfaces()
        }
        checkWallpaper(now: currentTime)

        if Settings.demo, !demoDone, currentTime - startTime > 3 { runDemo() }

        let t = CGFloat(currentTime.truncatingRemainder(dividingBy: 10_000))
        let wind: CGFloat = s.wind ? 28 * sin(t * 0.13) + 16 * sin(t * 0.37 + 1.3) : 0

        let global = NSEvent.mouseLocation
        let mouse = CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        let mouseMoved = abs(mouse.x - lastMouse.x) + abs(mouse.y - lastMouse.y) > 0.5
        lastMouse = mouse

        // Take clicks only over things that can be grabbed.
        let hot = wantsMouse(at: mouse)
        if hot != capturing {
            capturing = hot
            view?.window?.ignoresMouseEvents = !hot
        }
        station.setScale(hypot(mouse.x - stationPoint.x, mouse.y - stationPoint.y) < 20 ? 1.18 : 1)

        var surfaces: [Pile] = Array(piles.values)
        if let w = wallpaper { surfaces.append(w) }
        if mouseMoved {
            // The cursor works as a little shovel on windows and icons.
            for p in surfaces { shovel(p, mouse: mouse) }
        }
        if let g = ground { surfaces.append(g) }

        let radius: CGFloat = 90
        for f in flakes {
            f.phase += dt * 1.6
            let yOld = f.y
            f.x += (wind * (0.4 + f.size / 7.5) + sin(f.phase) * f.sway) * dt
            f.y -= f.vy * dt

            // Flakes swirl away from the cursor.
            let dx = f.x - mouse.x, dy = f.y - mouse.y
            let d2 = dx * dx + dy * dy
            if d2 < radius * radius, d2 > 0.01 {
                let d = sqrt(d2)
                let push = (1 - d / radius) * 260 * dt
                f.x += dx / d * push
                f.y += dy / d * push
            }

            var landed = false
            if f.lands {
                for p in surfaces where p.covers(f.x) {
                    let top = p.top(at: f.x)
                    if yOld >= top && f.y <= top {
                        p.add(at: f.x, amount: f.size * CGFloat.random(in: 0.18...0.42))
                        landed = true
                        break
                    }
                }
            }
            if landed || f.y < -10 {
                configure(f, anywhere: false)
            } else if f.x < -80 {
                f.x = size.width + 60
            } else if f.x > size.width + 80 {
                f.x = -60
            }
            f.node.position = CGPoint(x: f.x, y: f.y)
        }

        if !debris.isEmpty {
            var alive: [Flake] = []
            alive.reserveCapacity(debris.count)
            for f in debris {
                f.phase += dt * 3
                f.vy = min(340, f.vy + 260 * dt)
                f.vx *= max(0, 1 - 1.5 * dt)
                f.x += (f.vx + wind * 0.6 + sin(f.phase) * f.sway) * dt
                f.y -= f.vy * dt
                if f.y < -10 {
                    f.node.removeFromParent()
                } else {
                    f.node.position = CGPoint(x: f.x, y: f.y)
                    alive.append(f)
                }
            }
            debris = alive
        }

        updatePlow(dt: dt, time: t, now: currentTime)
        updateBalls(dt: dt)
        updateCables(dt: dt)
        for g in garlands.values { g.animate(time: t) }

        if currentTime - lastPathRebuild > 0.12 || currentTime < lastPathRebuild {
            lastPathRebuild = currentTime
            for p in surfaces where p.dirty { p.rebuildPath() }
            groundFill = ground?.fillRatio() ?? 0
        }
    }

    private func shovel(_ pile: Pile, mouse: CGPoint) {
        guard pile.covers(mouse.x) else { return }
        let i = pile.index(at: mouse.x)
        let edge = pile.y + pile.base[i]
        guard mouse.y >= edge - 4, mouse.y <= edge + pile.cap[i] + 8 else { return }
        let a = pile.index(at: mouse.x - 12), b = pile.index(at: mouse.x + 12)
        guard a <= b else { return }
        for k in a...b where pile.heights[k] > 0.5 {
            if Int.random(in: 0..<3) == 0 {
                spawnDebris(x: pile.columnX(k), y: pile.y + pile.base[k] + pile.heights[k])
            }
            pile.heights[k] *= 0.4
            pile.dirty = true
        }
    }
}
