import AppKit
import SpriteKit

// MARK: Drawing helpers

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

private func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

private func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                   _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

private func poly(_ pts: [(CGFloat, CGFloat)]) -> NSBezierPath {
    let p = NSBezierPath()
    for (i, pt) in pts.enumerated() {
        if i == 0 { p.move(to: NSPoint(x: pt.0, y: pt.1)) } else { p.line(to: NSPoint(x: pt.0, y: pt.1)) }
    }
    p.close()
    return p
}

private func line(_ pts: [(CGFloat, CGFloat)]) -> NSBezierPath {
    let p = NSBezierPath()
    for (i, pt) in pts.enumerated() {
        if i == 0 { p.move(to: NSPoint(x: pt.0, y: pt.1)) } else { p.line(to: NSPoint(x: pt.0, y: pt.1)) }
    }
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    return p
}

private func fill(_ p: NSBezierPath, _ c: NSColor) {
    c.setFill()
    p.fill()
}

/// Vertical gradient fill.
private func fill(_ p: NSBezierPath, top: NSColor, bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)?.draw(in: p, angle: 90)
}

private func stroke(_ p: NSBezierPath, _ c: NSColor, _ width: CGFloat) {
    c.setStroke()
    p.lineWidth = width
    p.stroke()
}

/// Renders into an offscreen bitmap so textures stay sharp on Retina displays.
private func render(_ size: CGSize, scale: CGFloat = 3, _ draw: () -> Void) -> CGImage {
    let w = Int(ceil(size.width * scale)), h = Int(ceil(size.height * scale))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

// MARK: Art

/// All sprites are drawn in code, so the app ships without image files.
final class Art {
    static let shared = Art()

    static let bulbSizes: [CGSize] = [
        CGSize(width: 11, height: 23),   // 0: classic candle bulbs
        CGSize(width: 15, height: 21),   // 1: onion bulbs
        CGSize(width: 11, height: 25),   // 2: long pastel bulbs
        CGSize(width: 17, height: 21),   // 3: globes
    ]
    static let bulbColors: [[NSColor]] = [
        [rgb(226, 44, 38), rgb(44, 168, 84), rgb(255, 150, 32), rgb(56, 116, 236), rgb(255, 212, 60)],
        [rgb(48, 142, 84), rgb(244, 140, 44), rgb(190, 32, 32), rgb(248, 198, 72)],
        [rgb(234, 62, 52), rgb(250, 170, 186), rgb(62, 150, 92), rgb(255, 238, 200)],
        [rgb(244, 140, 44), rgb(112, 180, 132), rgb(244, 166, 180), rgb(220, 46, 42)],
    ]
    static let loaderSize = CGSize(width: 180, height: 136)
    static let gondolaSize = CGSize(width: 44, height: 58)
    static let stationSize = CGSize(width: 46, height: 40)

    let flake: SKTexture
    let glow: SKTexture
    /// `[style][color]`
    let bulbs: [[SKTexture]]
    let loader: SKTexture
    let gondola: SKTexture
    let station: SKTexture
    let ball: SKTexture
    let face: SKTexture
    let buttons: SKTexture
    let hat: SKTexture
    let arms: SKTexture

    private init() {
        flake = SKTexture(cgImage: Art.softDot(hardness: 0.45))
        glow = SKTexture(cgImage: Art.softDot(hardness: 0.0))
        bulbs = Art.bulbColors.enumerated().map { style, colors in
            colors.map { SKTexture(cgImage: Art.bulb(style: style, color: $0)) }
        }
        loader = SKTexture(cgImage: Art.loaderImage())
        gondola = SKTexture(cgImage: Art.gondolaImage())
        station = SKTexture(cgImage: Art.stationImage())
        ball = SKTexture(cgImage: Art.ballImage())
        face = SKTexture(cgImage: Art.faceImage())
        buttons = SKTexture(cgImage: Art.buttonsImage())
        hat = SKTexture(cgImage: Art.hatImage())
        arms = SKTexture(cgImage: Art.armsImage())
    }

    // MARK: Small sprites

    static func softDot(hardness: CGFloat) -> CGImage {
        render(CGSize(width: 32, height: 32), scale: 2) {
            let g = NSGradient(colors: [
                NSColor(white: 1, alpha: 1),
                NSColor(white: 1, alpha: hardness > 0 ? 0.85 : 0.35),
                NSColor(white: 1, alpha: 0),
            ], atLocations: [0, max(0.2, hardness), 1], colorSpace: .sRGB)
            g?.draw(in: oval(16, 16, 16, 16), relativeCenterPosition: .zero)
        }
    }

    static func bulb(style: Int, color: NSColor) -> CGImage {
        let size = bulbSizes[style]
        return render(size, scale: 4) {
            let w = size.width, h = size.height, cx = w / 2
            let socketH: CGFloat = 5.5, socketW: CGFloat = style == 3 || style == 1 ? 6.5 : 5.5
            let gt = h - socketH + 1.2        // top of the glass
            let glass: NSBezierPath
            switch style {
            case 0:
                glass = NSBezierPath()
                glass.move(to: NSPoint(x: cx - 2.4, y: gt))
                glass.curve(to: NSPoint(x: cx, y: 0.4),
                            controlPoint1: NSPoint(x: cx - w * 0.74, y: gt - h * 0.30),
                            controlPoint2: NSPoint(x: cx - w * 0.36, y: 0.6))
                glass.curve(to: NSPoint(x: cx + 2.4, y: gt),
                            controlPoint1: NSPoint(x: cx + w * 0.36, y: 0.6),
                            controlPoint2: NSPoint(x: cx + w * 0.74, y: gt - h * 0.30))
                glass.close()
            case 1:
                glass = NSBezierPath()
                glass.move(to: NSPoint(x: cx - 2.8, y: gt))
                glass.curve(to: NSPoint(x: cx, y: 0.4),
                            controlPoint1: NSPoint(x: cx - w * 0.95, y: gt - h * 0.28),
                            controlPoint2: NSPoint(x: cx - w * 0.30, y: h * 0.16))
                glass.curve(to: NSPoint(x: cx + 2.8, y: gt),
                            controlPoint1: NSPoint(x: cx + w * 0.30, y: h * 0.16),
                            controlPoint2: NSPoint(x: cx + w * 0.95, y: gt - h * 0.28))
                glass.close()
            case 2:
                glass = rrect(1.6, 0.5, w - 3.2, gt - 0.5, (w - 3.2) / 2)
            default:
                let r = w / 2 - 0.8
                glass = oval(cx, gt - r + 0.6, r, r)
            }

            let light = color.blended(withFraction: 0.65, of: .white) ?? color
            let dark = color.blended(withFraction: 0.38, of: .black) ?? color
            NSGradient(colors: [light, color, dark], atLocations: [0, 0.5, 1], colorSpace: .sRGB)?
                .draw(in: glass, relativeCenterPosition: NSPoint(x: -0.25, y: 0.15))
            stroke(glass, dark.withAlphaComponent(0.55), 0.4)
            // Specular highlight makes the glass read as glass.
            fill(oval(cx - w * 0.16, gt - h * 0.26, w * 0.09, h * 0.11), NSColor(white: 1, alpha: 0.6))

            let socket = rrect(cx - socketW / 2, h - socketH, socketW, socketH, 1.2)
            fill(socket, top: rgb(46, 92, 62), bottom: rgb(18, 44, 28))
            fill(NSBezierPath(rect: NSRect(x: cx - socketW / 2, y: h - socketH + 1.6,
                                           width: socketW, height: 0.7)), rgb(110, 160, 124, 0.7))
        }
    }

    static func ballImage() -> CGImage {
        render(CGSize(width: 64, height: 64)) {
            let p = oval(32, 32, 31, 31)
            NSGradient(colors: [.white, rgb(236, 242, 250), rgb(198, 214, 234)],
                       atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
                .draw(in: p, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
            stroke(p, rgb(150, 172, 204, 0.75), 0.9)
            // A few soft dents so it does not look like a perfect disc.
            for (x, y, r) in [(20.0, 22.0, 5.0), (42.0, 16.0, 4.0), (46.0, 38.0, 6.0), (18.0, 44.0, 3.5)] {
                fill(oval(CGFloat(x), CGFloat(y), CGFloat(r), CGFloat(r) * 0.7), rgb(120, 150, 190, 0.10))
            }
        }
    }

    static func faceImage() -> CGImage {
        render(CGSize(width: 64, height: 64)) {
            fill(oval(23, 39, 3.4, 3.8), rgb(24, 24, 28))
            fill(oval(41, 39, 3.4, 3.8), rgb(24, 24, 28))
            fill(oval(22, 40.4, 1, 1), NSColor(white: 1, alpha: 0.7))
            fill(oval(40, 40.4, 1, 1), NSColor(white: 1, alpha: 0.7))
            fill(poly([(30, 33), (30, 26.5), (51, 28.5)]), top: rgb(255, 150, 40), bottom: rgb(226, 104, 14))
            for i in 0..<5 {
                let a = CGFloat.pi * (1.22 + 0.14 * CGFloat(i))
                fill(oval(32 + cos(a) * 14, 31 + sin(a) * 14, 1.5, 1.5), rgb(24, 24, 28))
            }
        }
    }

    static func buttonsImage() -> CGImage {
        render(CGSize(width: 64, height: 64)) {
            for y in [46.0, 32.0, 18.0] {
                fill(oval(32, CGFloat(y), 3.2, 3.2), rgb(24, 24, 28))
                fill(oval(31, CGFloat(y) + 1, 0.9, 0.9), NSColor(white: 1, alpha: 0.5))
            }
        }
    }

    static func hatImage() -> CGImage {
        render(CGSize(width: 64, height: 44)) {
            fill(rrect(15, 6, 34, 34, 3), top: rgb(58, 58, 64), bottom: rgb(22, 22, 26))
            fill(NSBezierPath(rect: NSRect(x: 15, y: 9, width: 34, height: 6)), rgb(200, 36, 42))
            fill(rrect(4, 2, 56, 7, 3.5), top: rgb(52, 52, 58), bottom: rgb(18, 18, 22))
        }
    }

    static func armsImage() -> CGImage {
        render(CGSize(width: 160, height: 50)) {
            let wood = rgb(98, 64, 34)
            stroke(line([(60, 8), (10, 40)]), wood, 3.2)
            stroke(line([(24, 31), (12, 22)]), wood, 2.4)
            stroke(line([(20, 34), (22, 46)]), wood, 2.4)
            stroke(line([(100, 8), (150, 42)]), wood, 3.2)
            stroke(line([(136, 32), (150, 26)]), wood, 2.4)
            stroke(line([(140, 35), (136, 47)]), wood, 2.4)
        }
    }

    // MARK: Cable car

    static func gondolaImage() -> CGImage {
        render(gondolaSize) {
            // Grip and hanger
            fill(rrect(13, 53, 18, 5, 2), top: rgb(120, 124, 132), bottom: rgb(60, 62, 68))
            fill(oval(17, 55.5, 2.2, 2.2), rgb(30, 30, 34))
            fill(oval(27, 55.5, 2.2, 2.2), rgb(30, 30, 34))
            stroke(line([(22, 53), (22, 36)]), rgb(70, 72, 78), 2.4)
            // Cabin
            let cabin = rrect(3, 2, 38, 34, 8)
            fill(cabin, top: rgb(226, 52, 50), bottom: rgb(156, 22, 30))
            stroke(cabin, rgb(96, 12, 18, 0.8), 0.8)
            fill(rrect(6, 33, 32, 4, 2), top: rgb(90, 92, 98), bottom: rgb(50, 52, 58))
            // Windows
            let glass = rrect(6.5, 15, 31, 15, 3.5)
            fill(glass, top: rgb(206, 234, 250), bottom: rgb(120, 172, 210))
            stroke(glass, rgb(70, 20, 24, 0.7), 0.7)
            fill(NSBezierPath(rect: NSRect(x: 21.2, y: 15, width: 1.6, height: 15)), rgb(150, 26, 32))
            fill(poly([(10, 30), (15, 30), (11, 15), (7, 15)]), NSColor(white: 1, alpha: 0.35))
            // Trim
            fill(NSBezierPath(rect: NSRect(x: 3.5, y: 9, width: 37, height: 2.2)), NSColor(white: 1, alpha: 0.85))
        }
    }

    static func stationImage() -> CGImage {
        render(stationSize) {
            // Mast hanging from the top of the screen
            fill(rrect(19, 18, 8, 22, 2), top: rgb(70, 74, 82), bottom: rgb(110, 114, 122))
            fill(rrect(8, 34, 30, 6, 2), top: rgb(60, 64, 72), bottom: rgb(92, 96, 104))
            // Bull wheel
            let wheel = oval(23, 15, 13, 13)
            fill(wheel, top: rgb(250, 196, 44), bottom: rgb(214, 148, 10))
            stroke(wheel, rgb(120, 78, 0, 0.9), 1)
            fill(oval(23, 15, 9, 9), top: rgb(54, 58, 66), bottom: rgb(34, 36, 42))
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                stroke(line([(23, 15), (23 + cos(a) * 9, 15 + sin(a) * 9)]), rgb(150, 154, 162), 1.2)
            }
            fill(oval(23, 15, 3, 3), top: rgb(240, 70, 60), bottom: rgb(170, 26, 26))
        }
    }

    // MARK: Snow loader

    static func loaderImage() -> CGImage {
        render(loaderSize) {
            let yellowTop = rgb(252, 196, 30), yellowBottom = rgb(214, 148, 6)
            let edge = rgb(110, 72, 0, 0.75)

            fill(oval(92, 4, 82, 4), NSColor(white: 0, alpha: 0.22))

            // Presents on the back
            let redBox = rrect(4, 4, 30, 26, 2)
            fill(redBox, top: rgb(222, 52, 48), bottom: rgb(160, 24, 28))
            fill(NSBezierPath(rect: NSRect(x: 16.5, y: 4, width: 5, height: 26)), top: rgb(250, 214, 96), bottom: rgb(206, 158, 40))
            fill(NSBezierPath(rect: NSRect(x: 4, y: 15, width: 30, height: 4.5)), top: rgb(250, 214, 96), bottom: rgb(206, 158, 40))
            let greenBox = rrect(9, 30, 22, 18, 2)
            fill(greenBox, top: rgb(64, 160, 84), bottom: rgb(30, 104, 52))
            fill(NSBezierPath(rect: NSRect(x: 18.2, y: 30, width: 3.6, height: 18)), rgb(214, 44, 44))
            fill(oval(16, 50.5, 4.6, 3), top: rgb(232, 60, 56), bottom: rgb(176, 28, 32))
            fill(oval(24, 50.5, 4.6, 3), top: rgb(232, 60, 56), bottom: rgb(176, 28, 32))
            fill(oval(20, 49.5, 2, 2), rgb(150, 20, 26))

            // Rubber track
            fill(rrect(38, 2, 98, 34, 17), top: rgb(52, 52, 56), bottom: rgb(20, 20, 22))
            var x: CGFloat = 50
            while x < 124 {
                fill(NSBezierPath(rect: NSRect(x: x, y: 34.6, width: 4, height: 2.4)), rgb(16, 16, 18))
                fill(NSBezierPath(rect: NSRect(x: x, y: 1, width: 4, height: 2.4)), rgb(16, 16, 18))
                x += 8
            }
            fill(rrect(44, 8, 86, 22, 11), top: rgb(44, 44, 48), bottom: rgb(70, 70, 76))
            for cx in [56.0, 87.0, 118.0] {
                fill(oval(CGFloat(cx), 19, 9.5, 9.5), top: rgb(124, 126, 132), bottom: rgb(70, 72, 78))
                stroke(oval(CGFloat(cx), 19, 9.5, 9.5), rgb(30, 30, 34), 0.8)
                fill(oval(CGFloat(cx), 19, 3.6, 3.6), top: rgb(200, 202, 208), bottom: rgb(130, 132, 138))
            }
            for cx in [71.5, 102.5] {
                fill(oval(CGFloat(cx), 12.5, 4.2, 4.2), top: rgb(110, 112, 118), bottom: rgb(64, 66, 72))
            }

            // Chassis and engine cover
            let chassis = poly([(40, 34), (132, 34), (137, 43), (133, 51), (40, 51)])
            fill(chassis, top: yellowTop, bottom: yellowBottom)
            stroke(chassis, edge, 0.8)
            let engine = rrect(38, 49, 36, 36, 5)
            fill(engine, top: yellowTop, bottom: yellowBottom)
            stroke(engine, edge, 0.8)
            for y in [58.0, 63.5, 69.0] {
                fill(rrect(43, CGFloat(y), 16, 2.2, 1), rgb(70, 46, 0, 0.6))
            }
            fill(rrect(47, 84, 4.5, 12, 1.5), top: rgb(90, 92, 98), bottom: rgb(48, 50, 56))

            // Cab
            let cab = poly([(68, 49), (112, 49), (117, 61), (111, 99), (72, 99), (68, 91)])
            fill(cab, top: rgb(62, 64, 70), bottom: rgb(30, 32, 36))
            let glass = poly([(74, 57), (108, 57), (111, 63), (106, 93), (76, 93), (74, 87)])
            fill(glass, top: rgb(204, 232, 248), bottom: rgb(112, 164, 202))
            fill(poly([(85, 92), (94, 92), (86, 58), (78, 58)]), NSColor(white: 1, alpha: 0.34))
            fill(poly([(97, 92), (100, 92), (93, 58), (90, 58)]), NSColor(white: 1, alpha: 0.2))
            let roof = rrect(67, 97, 48, 5.5, 2.5)
            fill(roof, top: yellowTop, bottom: yellowBottom)
            stroke(roof, edge, 0.7)
            fill(oval(114, 53.5, 2.6, 2.6), rgb(255, 244, 190))

            // Lift arm, cylinder and bucket
            stroke(line([(98, 50), (122, 57)]), rgb(176, 178, 186), 3.2)
            let arm = line([(57, 87), (124, 58), (141, 36)])
            stroke(arm, edge, 11)
            stroke(arm, rgb(240, 176, 14), 9)
            stroke(line([(60, 87.5), (123, 60.5)]), rgb(255, 214, 90, 0.8), 1.6)
            fill(oval(57, 87, 4, 4), top: rgb(90, 92, 98), bottom: rgb(40, 42, 46))
            fill(oval(124, 58, 3.4, 3.4), top: rgb(90, 92, 98), bottom: rgb(40, 42, 46))

            fill(oval(152, 28, 12, 9), top: .white, bottom: rgb(206, 220, 238))
            let bucket = poly([(134, 45), (149, 41), (174, 7), (170, 2), (136, 2), (130, 21)])
            fill(bucket, top: rgb(92, 94, 102), bottom: rgb(40, 42, 48))
            stroke(bucket, rgb(18, 18, 22, 0.8), 0.8)
            stroke(line([(137, 2.6), (172, 5.6)]), rgb(212, 214, 220), 2)

            // Elf hat on the roof
            let hat = NSBezierPath()
            hat.move(to: NSPoint(x: 74, y: 104))
            hat.line(to: NSPoint(x: 108, y: 104))
            hat.curve(to: NSPoint(x: 60, y: 119),
                      controlPoint1: NSPoint(x: 104, y: 126), controlPoint2: NSPoint(x: 80, y: 136))
            hat.curve(to: NSPoint(x: 74, y: 104),
                      controlPoint1: NSPoint(x: 70, y: 117), controlPoint2: NSPoint(x: 76, y: 112))
            hat.close()
            fill(hat, top: rgb(58, 168, 84), bottom: rgb(22, 104, 48))
            stroke(hat, rgb(10, 60, 26, 0.7), 0.7)
            let band = rrect(70, 101, 42, 7.5, 3.6)
            fill(band, top: rgb(232, 56, 54), bottom: rgb(170, 26, 32))
            let pom = oval(59, 118.5, 5.5, 5.5)
            fill(pom, top: rgb(240, 70, 64), bottom: rgb(168, 24, 30))
            fill(oval(57.4, 120.4, 1.6, 1.6), NSColor(white: 1, alpha: 0.5))
        }
    }

    // MARK: Preview sheet

    /// Writes a contact sheet of every sprite; used to review the artwork.
    static func dump(to directory: String) {
        let items: [(CGImage, CGSize)] =
            [(loaderImage(), loaderSize), (gondolaImage(), gondolaSize), (stationImage(), stationSize),
             (ballImage(), CGSize(width: 64, height: 64)), (faceImage(), CGSize(width: 64, height: 64)),
             (hatImage(), CGSize(width: 64, height: 44)), (armsImage(), CGSize(width: 160, height: 50))]
        let sheet = render(CGSize(width: 760, height: 330), scale: 2) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            fill(NSBezierPath(rect: NSRect(x: 0, y: 0, width: 760, height: 330)), rgb(28, 40, 58))
            var x: CGFloat = 10
            for (image, size) in items {
                ctx.draw(image, in: CGRect(x: x, y: 150, width: size.width, height: size.height))
                x += size.width + 12
            }
            x = 10
            for style in 0..<bulbSizes.count {
                for color in bulbColors[style] {
                    let s = bulbSizes[style]
                    let big = CGSize(width: s.width * 3, height: s.height * 3)
                    ctx.draw(bulb(style: style, color: color),
                             in: CGRect(x: x, y: 20, width: big.width, height: big.height))
                    x += big.width + 4
                }
                x += 14
            }
        }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: sheet)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("sheet.png"))
        }
    }
}
