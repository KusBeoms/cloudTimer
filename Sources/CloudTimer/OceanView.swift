import SwiftUI

/// Animated sea that rises from the bottom of its container.
/// `level` 0 shows nothing, 1 covers everything. `time` drives wave/bubble motion.
struct OceanView: View {
    var level: Double
    var time: Double

    private struct Wave {
        let freq: Double      // radians per point
        let speed: Double     // radians per second
        let phase: Double
        let amp: CGFloat
        let lift: CGFloat     // how far above the front surface this layer sits
    }

    private static let waves: [Wave] = [
        Wave(freq: 0.011, speed: 0.55, phase: 1.7, amp: 14, lift: 9),   // back
        Wave(freq: 0.016, speed: -0.80, phase: 4.1, amp: 10, lift: 4),  // middle
        Wave(freq: 0.021, speed: 1.15, phase: 0.0, amp: 8, lift: 0),    // front
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            guard w > 0, h > 0 else { return }

            // Empty tank backdrop.
            let tank = Path(CGRect(origin: .zero, size: size))
            ctx.fill(tank, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.045, green: 0.085, blue: 0.140),
                    Color(red: 0.030, green: 0.055, blue: 0.095),
                ]),
                startPoint: CGPoint(x: w / 2, y: 0),
                endPoint: CGPoint(x: w / 2, y: h)))
            ctx.fill(tank, with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.05), Color.clear]),
                center: CGPoint(x: w * 0.5, y: h * 0.35),
                startRadius: 0, endRadius: max(w, h) * 0.7))

            let lv = min(1, max(0, level))
            guard lv > 0 else { return }

            let maxAmp: CGFloat = 14
            let lo = -maxAmp * 1.5 - 9
            let hi = h + maxAmp * 1.5
            let surfaceY = hi + (lo - hi) * CGFloat(lv)

            func wavePath(_ wv: Wave) -> Path {
                var p = Path()
                let base = surfaceY - wv.lift
                p.move(to: CGPoint(x: 0, y: h + 2))
                var x: CGFloat = 0
                while x <= w + 4 {
                    let y = base + CGFloat(sin(Double(x) * wv.freq + time * wv.speed + wv.phase)) * wv.amp
                    p.addLine(to: CGPoint(x: x, y: y))
                    x += 4
                }
                p.addLine(to: CGPoint(x: w + 4, y: h + 2))
                p.closeSubpath()
                return p
            }

            func crestPath(_ wv: Wave) -> Path {
                var p = Path()
                let base = surfaceY - wv.lift
                var x: CGFloat = 0
                var first = true
                while x <= w + 4 {
                    let y = base + CGFloat(sin(Double(x) * wv.freq + time * wv.speed + wv.phase)) * wv.amp
                    if first { p.move(to: CGPoint(x: x, y: y)); first = false }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += 4
                }
                return p
            }

            let top = max(0, surfaceY - 30)

            // Back layer: pale translucent teal.
            ctx.fill(wavePath(Self.waves[0]), with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.45, green: 0.82, blue: 0.88).opacity(0.38),
                    Color(red: 0.20, green: 0.50, blue: 0.70).opacity(0.30),
                ]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))

            // Middle layer: translucent blue.
            ctx.fill(wavePath(Self.waves[1]), with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.30, green: 0.70, blue: 0.85).opacity(0.50),
                    Color(red: 0.12, green: 0.36, blue: 0.62).opacity(0.45),
                ]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))

            // Front layer: aqua at the surface fading to deep navy-blue.
            let front = Self.waves[2]
            let gradTop = max(-20, surfaceY - front.amp)
            let gradBottom = max(gradTop + 120, h)
            ctx.fill(wavePath(front), with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.56, green: 0.90, blue: 0.93), location: 0),
                    .init(color: Color(red: 0.16, green: 0.52, blue: 0.76), location: 0.38),
                    .init(color: Color(red: 0.06, green: 0.20, blue: 0.43), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: gradTop), endPoint: CGPoint(x: 0, y: gradBottom)))

            // Foam along the crest.
            ctx.stroke(crestPath(front), with: .color(.white.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Bubbles, only below the surface.
            for i in 0..<14 {
                let seed = Double(i) + 1
                let fx = fract(sin(seed * 12.9898) * 43758.5453)
                let fo = fract(sin(seed * 78.233) * 12345.6789)
                let r = CGFloat(2 + (i % 4))
                let speed = 16.0 + Double((i * 7) % 13) * 2.2
                let cycle = Double(h) + Double(r) * 2
                let travelled = (time * speed + fo * cycle).truncatingRemainder(dividingBy: cycle)
                let y = h + r - CGFloat(travelled)
                let wobble = CGFloat(sin(time * 0.9 + seed * 2.1)) * 6
                let x = CGFloat(fx) * (w - 16) + 8 + wobble
                guard y > surfaceY + maxAmp else { continue }
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                let alpha = 0.15 + 0.05 * Double(i % 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(alpha * 0.8)), lineWidth: 0.6)
            }
        }
        .accessibilityHidden(true)
    }

    private func fract(_ v: Double) -> Double { v - v.rounded(.down) }
}
