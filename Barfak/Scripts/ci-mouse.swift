// CI helper: simulates mouse drags so the automated screenshots also cover
// the interactive features. Usage: ci-mouse x1 y1 x2 y2  (top-left origin)
import CoreGraphics
import Foundation

let a = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard a.count == 4 else { exit(1) }

func post(_ type: CGEventType, _ x: Double, _ y: Double) {
    CGEvent(mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(20_000)
}

post(.mouseMoved, a[0], a[1])
usleep(500_000)
post(.leftMouseDown, a[0], a[1])
for i in 1...40 {
    let t = Double(i) / 40
    post(.leftMouseDragged, a[0] + (a[2] - a[0]) * t, a[1] + (a[3] - a[1]) * t)
}
post(.leftMouseUp, a[2], a[3])
