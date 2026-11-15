import AppKit
import SpriteKit

/// One falling snowflake.
private final class Flake {
    let node: SKSpriteNode
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vy: CGFloat = 0
    var size: CGFloat = 0
    var phase: CGFloat = 0
    var sway: CGFloat = 0
    /// Small "distant" flakes fall past windows, big ones settle on them.
    var lands = false

    init(texture: SKTexture) {
        node = SKSpriteNode(texture: texture)
    }
}

/// Snow settled on a horizontal edge (a window's top or the screen bottom).
private final class Pile {
    static let columnWidth: CGFloat = 3

    var globalFrame: CGRect
    /// Scene coordinates of the edge.
    var x0: CGFloat
    var y: CGFloat
    var segments: [ClosedRange<CGFloat>] = []
    var heights: [CGFloat]
    let maxHeight: CGFloat
    let node = SKShapeNode()
    var dirty = true

    init(globalFrame: CGRect, x0: CGFloat, y: CGFloat, width: CGFloat, maxHeight: CGFloat) {
        self.globalFrame = globalFrame
        self.x0 = x0
        self.y = y
        self.maxHeight = maxHeight
        heights = Array(repeating: 0, count: max(1, Int(ceil(width / Pile.columnWidth))))
        node.fillColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        node.strokeColor = .clear
        node.lineWidth = 0
        node.zPosition = 10
    }

    func index(at x: CGFloat) -> Int {
        min(heights.count - 1, max(0, Int((x - x0) / Pile.columnWidth)))
    }

    func covers(_ x: CGFloat) -> Bool {
        for s in segments where s.contains(x) { return true }
        return false
    }

    func top(at x: CGFloat) -> CGFloat { y + heights[index(at: x)] }

    func add(at x: CGFloat, amount: CGFloat) {
        let i = index(at: x)
        heights[i] += amount
        if i > 0 { heights[i - 1] += amount * 0.5 }
        if i < heights.count - 1 { heights[i + 1] += amount * 0.5 }
        // Let steep heaps slide sideways so the pile looks soft.
        let lo = max(0, i - 4), hi = min(heights.count - 2, i + 4)
        if lo <= hi {
            for k in lo...hi {
                let diff = heights[k] - heights[k + 1]
                if abs(diff) > 1.5 {
                    heights[k] -= diff * 0.25
                    heights[k + 1] += diff * 0.25
                }
            }
        }
        for k in max(0, i - 1)...min(heights.count - 1, i + 1) where heights[k] > maxHeight {
            heights[k] = maxHeight
        }
        dirty = true
    }

    func rebuildPath() {
        dirty = false
        let path = CGMutablePath()
        var any = false
        for s in segments {
            let i0 = index(at: s.lowerBound), i1 = index(at: s.upperBound)
            guard i1 > i0 else { continue }
            var peak: CGFloat = 0
            for i in i0...i1 { peak = max(peak, heights[i]) }
            guard peak > 0.6 else { continue }
            any = true
            path.move(to: CGPoint(x: s.lowerBound, y: y))
            for i in i0...i1 {
                let px = min(s.upperBound, max(s.lowerBound,
                             x0 + (CGFloat(i) + 0.5) * Pile.columnWidth))
                path.addLine(to: CGPoint(x: px, y: y + heights[i]))
            }
            path.addLine(to: CGPoint(x: s.upperBound, y: y))
            path.closeSubpath()
        }
        node.path = any ? path : nil
    }
}

/// The snow simulation for a single screen.
final class SnowScene: SKScene {
    /// Screen frame in global Cocoa coordinates.
    private let screenFrame: CGRect
    private let texture: SKTexture

    private var flakes: [Flake] = []
    private var debris: [Flake] = []
    private var piles: [CGWindowID: Pile] = [:]
    private var ground: Pile?

    private var lastTime: TimeInterval = 0
    private var lastPathRebuild: TimeInterval = 0
    private var lastMouse = CGPoint(x: -1000, y: -1000)

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        self.texture = SnowScene.makeFlakeTexture()
        super.init(size: screenFrame.size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private static func makeFlakeTexture() -> SKTexture {
        let side: CGFloat = 32
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 1, alpha: 1),
                NSColor(calibratedWhite: 1, alpha: 0.85),
                NSColor(calibratedWhite: 1, alpha: 0),
            ], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        return SKTexture(image: image)
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
        var added = 0
        while flakes.count < target && added < 12 {
            let f = Flake(texture: texture)
            configure(f, anywhere: flakes.count < target / 3)
            addChild(f.node)
            flakes.append(f)
            added += 1
        }
        var removed = 0
        while flakes.count > target && removed < 12 {
            flakes.removeLast().node.removeFromParent()
            removed += 1
        }
    }

    private func spawnDebris(x: CGFloat, y: CGFloat) {
        guard debris.count < 500 else { return }
        let f = Flake(texture: texture)
        f.size = CGFloat.random(in: 3...6)
        f.vy = CGFloat.random(in: 10...60)
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

    // MARK: Piles

    private func dump(_ pile: Pile) {
        var i = 0
        while i < pile.heights.count {
            let h = pile.heights[i]
            let x = pile.x0 + (CGFloat(i) + 0.5) * Pile.columnWidth
            if h > 2, pile.covers(x) {
                spawnDebris(x: x, y: pile.y + CGFloat.random(in: 0...h))
            }
            i += 2
        }
    }

    private func removePile(_ id: CGWindowID, falling: Bool) {
        guard let pile = piles.removeValue(forKey: id) else { return }
        if falling { dump(pile) }
        pile.node.removeFromParent()
    }

    private func syncPiles(now: TimeInterval) {
        guard Settings.shared.accumulate else {
            for id in Array(piles.keys) { removePile(id, falling: true) }
            if let g = ground { dump(g); g.node.removeFromParent(); ground = nil }
            return
        }

        if ground == nil || abs((ground?.globalFrame.width ?? 0) - size.width) > 0.5 {
            ground?.node.removeFromParent()
            let g = Pile(globalFrame: CGRect(x: 0, y: 0, width: size.width, height: 0),
                         x0: 0, y: 0, width: size.width, maxHeight: 24)
            g.segments = [0...size.width]
            addChild(g.node)
            ground = g
        }

        var seen = Set<CGWindowID>()
        for s in WindowTracker.shared.surfaces(now: now) {
            let ly = s.frame.maxY - screenFrame.minY
            guard ly > 30, ly < size.height - 4 else { continue }
            var segs: [ClosedRange<CGFloat>] = []
            for g in s.segments {
                let a = max(0, g.lowerBound - screenFrame.minX)
                let b = min(size.width, g.upperBound - screenFrame.minX)
                if b - a >= 12 { segs.append(a...b) }
            }
            guard !segs.isEmpty else { continue }
            seen.insert(s.windowID)

            if let pile = piles[s.windowID] {
                let old = pile.globalFrame
                let resized = abs(old.width - s.frame.width) > 0.5
                let moved = abs(old.minX - s.frame.minX) > 0.5 || abs(old.maxY - s.frame.maxY) > 0.5
                if resized {
                    removePile(s.windowID, falling: true)
                } else {
                    if moved {
                        // The window was dragged: the snow falls off.
                        dump(pile)
                        for i in pile.heights.indices { pile.heights[i] = 0 }
                        pile.globalFrame = s.frame
                        pile.x0 = s.frame.minX - screenFrame.minX
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
            let pile = Pile(globalFrame: s.frame, x0: s.frame.minX - screenFrame.minX,
                            y: ly, width: s.frame.width, maxHeight: 13)
            pile.segments = segs
            addChild(pile.node)
            piles[s.windowID] = pile
        }
        for id in Array(piles.keys) where !seen.contains(id) {
            removePile(id, falling: true)
        }
    }

    /// The cursor works as a little shovel.
    private func shovel(_ pile: Pile, mouse: CGPoint) {
        guard mouse.y >= pile.y - 4, mouse.y <= pile.y + pile.maxHeight + 8,
              pile.covers(mouse.x) else { return }
        let a = pile.index(at: mouse.x - 12), b = pile.index(at: mouse.x + 12)
        guard a <= b else { return }
        for i in a...b where pile.heights[i] > 0.5 {
            if Int.random(in: 0..<3) == 0 {
                spawnDebris(x: pile.x0 + (CGFloat(i) + 0.5) * Pile.columnWidth,
                            y: pile.y + pile.heights[i])
            }
            pile.heights[i] *= 0.4
            pile.dirty = true
        }
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(min(1.0 / 30.0, max(0, currentTime - lastTime)))
        lastTime = currentTime
        guard dt > 0 else { return }

        adjustFlakeCount()
        syncPiles(now: currentTime)

        let t = CGFloat(currentTime.truncatingRemainder(dividingBy: 10_000))
        let wind: CGFloat = Settings.shared.wind
            ? 28 * sin(t * 0.13) + 16 * sin(t * 0.37 + 1.3) : 0

        let global = NSEvent.mouseLocation
        let mouse = CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        let mouseMoved = abs(mouse.x - lastMouse.x) + abs(mouse.y - lastMouse.y) > 0.5
        lastMouse = mouse

        var surfaces: [Pile] = Array(piles.values)
        if let g = ground { surfaces.append(g) }

        if mouseMoved {
            for p in surfaces { shovel(p, mouse: mouse) }
        }

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
                        p.add(at: f.x, amount: f.size * 0.3)
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
                f.x += (wind * 0.6 + sin(f.phase) * f.sway) * dt
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

        if currentTime - lastPathRebuild > 0.12 || currentTime < lastPathRebuild {
            lastPathRebuild = currentTime
            for p in surfaces where p.dirty { p.rebuildPath() }
        }
    }
}
