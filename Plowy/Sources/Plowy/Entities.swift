import AppKit
import SpriteKit

/// One falling snowflake (or a piece of loose snow knocked off a pile).
final class Flake {
    let node: SKSpriteNode
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var size: CGFloat = 0
    var phase: CGFloat = 0
    var sway: CGFloat = 0
    /// Small "distant" flakes fall past surfaces, big ones settle on them.
    var lands = false

    init(texture: SKTexture) {
        node = SKSpriteNode(texture: texture)
    }
}

/// Snow settled on an edge: a window top, an icon, the screen bottom, or the
/// outline of the wallpaper's subject.
final class Pile {
    static let columnWidth: CGFloat = 3

    let key: String
    var globalFrame: CGRect
    /// Scene coordinates of the edge.
    var x0: CGFloat
    var y: CGFloat
    var segments: [ClosedRange<CGFloat>] = []
    var heights: [CGFloat]
    /// Maximum snow height per column; uneven so full piles look natural.
    let cap: [CGFloat]
    /// Per-column offset of the edge above `y` (flat edges use zeros).
    let base: [CGFloat]
    private let contoured: Bool
    let node = SKShapeNode()
    var dirty = true

    init(key: String, globalFrame: CGRect, x0: CGFloat, y: CGFloat,
         cap: [CGFloat], base: [CGFloat]? = nil) {
        self.key = key
        self.globalFrame = globalFrame
        self.x0 = x0
        self.y = y
        self.cap = cap
        self.base = base ?? Array(repeating: 0, count: cap.count)
        contoured = base != nil
        heights = Array(repeating: 0, count: cap.count)
        node.fillColor = NSColor(srgbRed: 0.99, green: 0.995, blue: 1, alpha: 0.97)
        node.strokeColor = NSColor(srgbRed: 0.74, green: 0.81, blue: 0.90, alpha: 0.9)
        node.lineWidth = 0.8
        node.zPosition = 10
    }

    /// Lumpy height limits built from a few sine waves plus fine jitter.
    static func noisyCaps(width: CGFloat, low: CGFloat, high: CGFloat) -> [CGFloat] {
        let count = max(1, Int(ceil(width / columnWidth)))
        let p1 = CGFloat.random(in: 0...6.28), p2 = CGFloat.random(in: 0...6.28)
        let p3 = CGFloat.random(in: 0...6.28), p4 = CGFloat.random(in: 0...6.28)
        let w1 = CGFloat.random(in: 70...110), w2 = CGFloat.random(in: 30...46)
        let w3 = CGFloat.random(in: 11...17), w4 = CGFloat.random(in: 210...330)
        return (0..<count).map { i in
            let x = CGFloat(i) * columnWidth
            var n = 0.34 * sin(x / w1 + p1) + 0.22 * sin(x / w2 + p2)
            n += 0.12 * sin(x / w3 + p3) + 0.32 * sin(x / w4 + p4)
            let unit = min(1, max(0, 0.5 + 0.5 * n + CGFloat.random(in: -0.04...0.04)))
            return low + (high - low) * unit
        }
    }

    func index(at x: CGFloat) -> Int {
        min(heights.count - 1, max(0, Int((x - x0) / Pile.columnWidth)))
    }

    func columnX(_ i: Int) -> CGFloat { x0 + (CGFloat(i) + 0.5) * Pile.columnWidth }

    func covers(_ x: CGFloat) -> Bool {
        for s in segments where s.contains(x) { return true }
        return false
    }

    func height(at x: CGFloat) -> CGFloat { heights[index(at: x)] }

    func top(at x: CGFloat) -> CGFloat {
        let i = index(at: x)
        return y + base[i] + heights[i]
    }

    func add(at x: CGFloat, amount: CGFloat) {
        let i = index(at: x)
        let n = heights.count
        heights[i] += amount
        if i > 0 { heights[i - 1] += amount * CGFloat.random(in: 0.2...0.7) }
        if i < n - 1 { heights[i + 1] += amount * CGFloat.random(in: 0.2...0.7) }
        // Let steep heaps slide sideways, but keep some roughness.
        let lo = max(0, i - 4), hi = min(n - 2, i + 4)
        if lo <= hi {
            for k in lo...hi {
                let diff = heights[k] - heights[k + 1]
                if abs(diff) > 2.6 {
                    heights[k] -= diff * 0.22
                    heights[k + 1] += diff * 0.22
                }
            }
        }
        for k in max(0, i - 5)...min(n - 1, i + 5) where heights[k] > cap[k] {
            heights[k] = cap[k]
        }
        dirty = true
    }

    /// How full the visible part of the pile is, 0...1.
    func fillRatio() -> CGFloat {
        var have: CGFloat = 0, room: CGFloat = 0
        for s in segments {
            let i0 = index(at: s.lowerBound + 0.01), i1 = index(at: s.upperBound - 0.01)
            guard i1 >= i0 else { continue }
            for i in i0...i1 { have += heights[i]; room += cap[i] }
        }
        return room > 0 ? have / room : 0
    }

    func rebuildPath() {
        dirty = false
        let path = CGMutablePath()
        var any = false
        for s in segments {
            let i0 = index(at: s.lowerBound + 0.01), i1 = index(at: s.upperBound - 0.01)
            guard i1 > i0 else { continue }
            var peak: CGFloat = 0
            for i in i0...i1 { peak = max(peak, heights[i]) }
            guard peak > 0.6 else { continue }
            any = true
            path.move(to: CGPoint(x: s.lowerBound, y: y + base[i0]))
            for i in i0...i1 {
                let px = min(s.upperBound, max(s.lowerBound, columnX(i)))
                path.addLine(to: CGPoint(x: px, y: y + base[i] + heights[i]))
            }
            path.addLine(to: CGPoint(x: s.upperBound, y: y + base[i1]))
            if contoured {
                for i in stride(from: i1, through: i0, by: -1) {
                    let px = min(s.upperBound, max(s.lowerBound, columnX(i)))
                    path.addLine(to: CGPoint(x: px, y: y + base[i]))
                }
            }
            path.closeSubpath()
        }
        node.path = any ? path : nil
    }
}

/// A string of blinking lights draped along the top of a window.
final class Garland {
    let node = SKNode()
    private var bulbs: [(bulb: SKSpriteNode, glow: SKSpriteNode, phase: CGFloat)] = []
    private var signature = ""

    init() { node.zPosition = 12 }

    func update(segments: [ClosedRange<CGFloat>], y: CGFloat, style: Int) {
        let sig = "\(style)|\(Int(y))|" + segments
            .map { "\(Int($0.lowerBound))-\(Int($0.upperBound))" }.joined(separator: ",")
        guard sig != signature else { return }
        signature = sig
        rebuild(segments: segments, y: y, style: style)
    }

    private func rebuild(segments: [ClosedRange<CGFloat>], y: CGFloat, style: Int) {
        node.removeAllChildren()
        bulbs.removeAll()
        let art = Art.shared
        let size = Art.bulbSizes[style]
        let colors = Art.bulbColors[style]
        let spacing: CGFloat = [24, 27, 25, 30][style]
        let tilt: CGFloat = [0.30, 0.14, 0.34, 0.0][style]
        let wire = CGMutablePath()
        var index = 0

        for s in segments {
            let a = s.lowerBound + 8, b = s.upperBound - 8
            let length = b - a
            guard length >= 50, bulbs.count < 140 else { continue }
            let spans = max(1, Int((length / 130).rounded()))
            let span = length / CGFloat(spans)
            let perSpan = max(2, Int(span / spacing))
            for k in 0..<spans {
                let p0 = CGPoint(x: a + CGFloat(k) * span, y: y - 2)
                let p1 = CGPoint(x: p0.x + span, y: y - 2)
                let c = CGPoint(x: (p0.x + p1.x) / 2, y: y - 2 - 22)
                wire.move(to: p0)
                wire.addQuadCurve(to: p1, control: c)
                for j in 0..<perSpan {
                    let u = (CGFloat(j) + 0.5) / CGFloat(perSpan)
                    let v = 1 - u
                    let pt = CGPoint(x: v * v * p0.x + 2 * u * v * c.x + u * u * p1.x,
                                     y: v * v * p0.y + 2 * u * v * c.y + u * u * p1.y)
                    let colorIndex = index % colors.count
                    let angle = (index % 2 == 0 ? tilt : -tilt) + CGFloat.random(in: -0.06...0.06)

                    let glow = SKSpriteNode(texture: art.glow)
                    glow.size = CGSize(width: size.width * 3.6, height: size.width * 3.6)
                    glow.color = colors[colorIndex]
                    glow.colorBlendFactor = 1
                    glow.blendMode = .add
                    glow.position = CGPoint(x: pt.x + sin(angle) * size.height * 0.6,
                                            y: pt.y - cos(angle) * size.height * 0.6)
                    glow.zPosition = 0
                    node.addChild(glow)

                    let bulb = SKSpriteNode(texture: art.bulbs[style][colorIndex])
                    bulb.size = size
                    bulb.anchorPoint = CGPoint(x: 0.5, y: 1)
                    bulb.position = pt
                    bulb.zRotation = angle
                    bulb.color = .black
                    bulb.zPosition = 2
                    node.addChild(bulb)

                    bulbs.append((bulb, glow, CGFloat.random(in: 0...6.28)))
                    index += 1
                }
            }
        }

        let wireNode = SKShapeNode(path: wire)
        wireNode.strokeColor = NSColor(srgbRed: 0.07, green: 0.22, blue: 0.13, alpha: 1)
        wireNode.fillColor = .clear
        wireNode.lineWidth = 1.3
        wireNode.zPosition = 1
        node.addChild(wireNode)
    }

    /// Cycles through three blink programs: chase, alternate and twinkle.
    func animate(time t: CGFloat) {
        let program = Int(t / 9) % 3
        for (i, item) in bulbs.enumerated() {
            var b: CGFloat
            switch program {
            case 0:
                b = (Int(t * 3) + i) % 4 == 0 ? 1 : 0.18
            case 1:
                b = (Int(t * 1.4) + i) % 2 == 0 ? 1 : 0.15
            default:
                b = 0.55 + 0.45 * sin(t * 2.6 + item.phase)
            }
            b = min(1, max(0, b))
            item.glow.alpha = 0.12 + 0.78 * b
            item.bulb.colorBlendFactor = (1 - b) * 0.42
        }
    }
}

/// A snowball rolled by the user. Three stacked balls become a snowman.
final class Snowball {
    enum Role { case plain, head, torso }

    let node: SKSpriteNode
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat
    var vy: CGFloat = 0
    var held = false
    weak var support: Snowball?
    var role: Role = .plain
    private var decorations: [SKNode] = []

    init(x: CGFloat, y: CGFloat, r: CGFloat) {
        self.x = x
        self.y = y
        self.r = r
        node = SKSpriteNode(texture: Art.shared.ball)
        node.zPosition = 20
        sync()
    }

    func sync() {
        node.position = CGPoint(x: x, y: y)
        node.size = CGSize(width: r * 2, height: r * 2)
    }

    func setRole(_ newRole: Role) {
        guard newRole != role else { return }
        role = newRole
        decorations.forEach { $0.removeFromParent() }
        decorations.removeAll()
        let art = Art.shared
        let d = r * 2
        func add(_ texture: SKTexture, _ size: CGSize, _ position: CGPoint, _ z: CGFloat) {
            let n = SKSpriteNode(texture: texture)
            n.size = size
            n.position = position
            n.zPosition = z
            node.addChild(n)
            decorations.append(n)
        }
        switch newRole {
        case .plain:
            break
        case .head:
            node.zRotation = 0
            add(art.face, CGSize(width: d, height: d), .zero, 1)
            add(art.hat, CGSize(width: d, height: d * 0.69), CGPoint(x: 0, y: r * 0.72 + d * 0.3), 2)
        case .torso:
            node.zRotation = 0
            add(art.buttons, CGSize(width: d, height: d), .zero, 1)
            add(art.arms, CGSize(width: d * 2.5, height: d * 0.78), CGPoint(x: 0, y: r * 0.5), -1)
        }
    }
}

/// A rope from the station to a window, an icon or a point, with a gondola.
final class Cable {
    enum Anchor {
        case window(id: CGWindowID, dx: CGFloat, dy: CGFloat)
        case fixed(CGPoint)
    }

    let anchor: Anchor
    let node = SKNode()
    private let rope = SKShapeNode()
    private let car = SKSpriteNode(texture: Art.shared.gondola)
    private let peg = SKShapeNode(circleOfRadius: 3.5)
    private var end = CGPoint(x: -1, y: -1)
    private var start = CGPoint.zero
    private var t: CGFloat = 0
    private var direction: CGFloat = 1
    private var pause: CGFloat = 0.6

    init(anchor: Anchor) {
        self.anchor = anchor
        node.zPosition = 14
        rope.strokeColor = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1)
        rope.fillColor = .clear
        rope.lineWidth = 1.6
        node.addChild(rope)
        peg.fillColor = NSColor(srgbRed: 0.85, green: 0.2, blue: 0.2, alpha: 1)
        peg.strokeColor = NSColor(white: 0.1, alpha: 0.8)
        peg.lineWidth = 0.8
        peg.zPosition = 1
        node.addChild(peg)
        car.size = Art.gondolaSize
        car.anchorPoint = CGPoint(x: 0.5, y: 1)
        car.zPosition = 2
        node.addChild(car)
    }

    private func control() -> CGPoint {
        let dist = hypot(end.x - start.x, end.y - start.y)
        return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - min(46, dist * 0.09))
    }

    func update(start: CGPoint, end newEnd: CGPoint, dt: CGFloat) {
        if newEnd != end || start != self.start {
            end = newEnd
            self.start = start
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control())
            rope.path = path
            peg.position = end
        }
        let length = max(60, hypot(end.x - start.x, end.y - start.y))
        if pause > 0 {
            pause -= dt
        } else {
            t += direction * 75 * dt / length
            if t >= 1 { t = 1; direction = -1; pause = 1.4 }
            if t <= 0 { t = 0; direction = 1; pause = 1.4 }
        }
        // Ease in and out near the ends.
        let u = t * t * (3 - 2 * t), v = 1 - u
        let c = control()
        car.position = CGPoint(x: v * v * start.x + 2 * u * v * c.x + u * u * end.x,
                               y: v * v * start.y + 2 * u * v * c.y + u * u * end.y + 1.5)
    }
}
