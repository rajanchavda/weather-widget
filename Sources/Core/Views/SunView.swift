import SwiftUI

struct SunView: View {
    let width: CGFloat
    let height: CGFloat
    let freezeDate: Date?

    init(width: CGFloat, height: CGFloat, freezeDate: Date? = nil) {
        self.width = width
        self.height = height
        self.freezeDate = freezeDate
    }

    /// Right of center, clear of the notch on notched displays.
    static let horizontalOffset: CGFloat = 140

    private static let warmWhite = Color(red: 1.0, green: 0.97, blue: 0.88)
    private static let gold = Color(red: 1.0, green: 0.84, blue: 0.52)
    private static let amber = Color(red: 1.0, green: 0.66, blue: 0.30)

    var body: some View {
        if let freezeDate {
            Canvas { context, size in
                render(at: freezeDate.timeIntervalSinceReferenceDate, context: &context, size: size)
            }
        } else {
            TimelineView(.animation(minimumInterval: OverlayAnimation.frameInterval)) { timeline in
                Canvas { context, size in
                    render(at: timeline.date.timeIntervalSinceReferenceDate, context: &context, size: size)
                }
            }
        }
    }

    private func render(at time: TimeInterval, context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2 + Self.horizontalOffset, y: size.height / 2)
        // Everything scales with the bar, which is about 24pt tall without a notch and 37pt with one.
        let unit = size.height
        // One slow breath shared by the glow layers, so they swell together instead of flickering.
        let breath = sin(time * 2 * .pi / 9)

        drawBloom(center: center, unit: unit, breath: breath, context: &context)
        drawRays(center: center, unit: unit, time: time, context: &context)
        drawStreak(center: center, unit: unit, breath: breath, context: &context)
        drawDisc(center: center, unit: unit, breath: breath, context: &context)
        drawGhosts(sun: center, size: size, time: time, context: &context)
        drawMotes(sun: center, size: size, time: time, context: &context)
    }

    // MARK: - Layers

    /// Warm light spilling sideways across the bar; squashed vertically because the bar is so short.
    private func drawBloom(center: CGPoint, unit: CGFloat, breath: Double, context: inout GraphicsContext) {
        let radius = unit * 5.0 * (1 + breath * 0.06)
        context.drawLayer { ctx in
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: 1, y: 0.35)
            ctx.fill(
                Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Self.gold.opacity(0.26), location: 0),
                        .init(color: Self.amber.opacity(0.08), location: 0.35),
                        .init(color: Self.amber.opacity(0), location: 1)
                    ]),
                    center: .zero, startRadius: 0, endRadius: radius
                )
            )
        }
    }

    /// Two counter-rotating sets of tapered rays that fade toward their tips. Each ray's length
    /// drifts on its own phase, so the corona shimmers rather than spinning like a wheel.
    private func drawRays(center: CGPoint, unit: CGFloat, time: TimeInterval, context: inout GraphicsContext) {
        let sets: [(count: Int, length: CGFloat, halfWidth: Double, speed: Double, opacity: Double)] = [
            (8, unit * 2.4, 0.045, 0.035, 0.30),
            (13, unit * 1.4, 0.028, -0.05, 0.22)
        ]

        for (setIndex, set) in sets.enumerated() {
            for i in 0..<set.count {
                let phase = Double(i) * 2.399 + Double(setIndex) * 1.1
                let angle = time * set.speed + Double.pi * 2 * Double(i) / Double(set.count)
                let length = set.length * (0.7 + 0.3 * (0.5 + 0.5 * sin(time * 0.6 + phase)))
                let opacity = set.opacity * (0.75 + 0.25 * sin(time * 0.45 + phase * 1.3))

                var ray = Path()
                ray.move(to: center)
                ray.addLine(to: point(from: center, angle: angle - set.halfWidth, distance: length))
                ray.addLine(to: point(from: center, angle: angle + set.halfWidth, distance: length))
                ray.closeSubpath()

                context.fill(
                    ray,
                    with: .radialGradient(
                        Gradient(colors: [Self.warmWhite.opacity(opacity), Self.gold.opacity(opacity * 0.4), Self.gold.opacity(0)]),
                        center: center, startRadius: unit * 0.15, endRadius: length
                    )
                )
            }
        }
    }

    /// Anamorphic streak through the sun: a thin bright core inside a wider, fainter haze.
    private func drawStreak(center: CGPoint, unit: CGFloat, breath: Double, context: inout GraphicsContext) {
        let length = unit * 11 * (1 + breath * 0.08)
        let layers: [(thickness: CGFloat, opacity: Double)] = [(unit * 0.16, 0.14), (unit * 0.04, 0.45)]

        for layer in layers {
            let rect = CGRect(x: center.x - length / 2, y: center.y - layer.thickness / 2, width: length, height: layer.thickness)
            context.fill(
                Path(ellipseIn: rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.75, green: 0.88, blue: 1.0).opacity(0), location: 0),
                        .init(color: Color(red: 0.80, green: 0.90, blue: 1.0).opacity(layer.opacity * 0.6), location: 0.3),
                        .init(color: Self.warmWhite.opacity(layer.opacity), location: 0.5),
                        .init(color: Color(red: 0.80, green: 0.90, blue: 1.0).opacity(layer.opacity * 0.6), location: 0.7),
                        .init(color: Color(red: 0.75, green: 0.88, blue: 1.0).opacity(0), location: 1)
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: center.y),
                    endPoint: CGPoint(x: rect.maxX, y: center.y)
                )
            )
        }
    }

    /// Corona and disc as one soft radial falloff: white-hot center, golden rim, amber haze. No hard edge.
    private func drawDisc(center: CGPoint, unit: CGFloat, breath: Double, context: inout GraphicsContext) {
        let coronaRadius = unit * 0.95 * (1 + breath * 0.05)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - coronaRadius, y: center.y - coronaRadius, width: coronaRadius * 2, height: coronaRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Self.warmWhite.opacity(0.95), location: 0.16),
                    .init(color: Self.gold.opacity(0.55), location: 0.26),
                    .init(color: Self.amber.opacity(0.18), location: 0.5),
                    .init(color: Self.amber.opacity(0), location: 1)
                ]),
                center: center, startRadius: 0, endRadius: coronaRadius
            )
        )
    }

    /// Lens ghosts sit on the line from the sun through the middle of the bar, as a real lens
    /// reflects them. A slow drift of the virtual light source moves the far ghosts the most.
    private func drawGhosts(sun: CGPoint, size: CGSize, time: TimeInterval, context: inout GraphicsContext) {
        let source = CGPoint(x: sun.x + sin(time * 0.11) * 12, y: sun.y + sin(time * 0.17) * 3)
        let mirror = CGPoint(x: size.width - source.x, y: size.height - source.y)
        let unit = size.height

        let ghosts: [(position: Double, radius: CGFloat, color: Color, opacity: Double, ring: Bool)] = [
            (0.22, 0.10, Color(red: 1.0, green: 0.75, blue: 0.4), 0.22, false),
            (0.38, 0.22, Color(red: 0.55, green: 0.85, blue: 0.75), 0.12, true),
            (0.55, 0.08, Color(red: 0.7, green: 0.8, blue: 1.0), 0.25, false),
            (0.78, 0.30, Color(red: 0.75, green: 0.6, blue: 1.0), 0.08, true),
            (1.05, 0.14, Color(red: 0.5, green: 0.8, blue: 1.0), 0.14, false)
        ]

        for (index, ghost) in ghosts.enumerated() {
            let x = source.x + (mirror.x - source.x) * ghost.position
            let y = source.y + (mirror.y - source.y) * ghost.position
            let radius = unit * ghost.radius
            let opacity = ghost.opacity * (0.8 + 0.2 * sin(time * 0.5 + Double(index) * 1.9))
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: ghost.color.opacity(ghost.ring ? opacity * 0.3 : opacity), location: 0),
                        .init(color: ghost.color.opacity(opacity * 0.6), location: ghost.ring ? 0.85 : 0.5),
                        .init(color: ghost.color.opacity(0), location: 1)
                    ]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius
                )
            )
        }
    }

    /// Dust motes drifting in the light. They are barely visible far away and glint as they pass the sun.
    private func drawMotes(sun: CGPoint, size: CGSize, time: TimeInterval, context: inout GraphicsContext) {
        let moteCount = 18
        let span = Double(size.width) * 0.6
        let startX = Double(sun.x) - span / 2

        for i in 0..<moteCount {
            let seed = Double(i)
            let period = 22.0 + (seed * 7.3).truncatingRemainder(dividingBy: 14.0)
            let progress = ((time + seed * 37.0) / period).truncatingRemainder(dividingBy: 1.0)

            let x = startX + (progress + seed / Double(moteCount)).truncatingRemainder(dividingBy: 1.0) * span
            let lane = (seed * 0.618).truncatingRemainder(dividingBy: 1.0)
            let y = Double(size.height) * (0.15 + 0.7 * lane) + sin(time * 0.4 + seed * 2.1) * 2.0

            let distance = abs(x - Double(sun.x))
            let glint = exp(-distance / (Double(size.height) * 4))
            let twinkle = 0.6 + 0.4 * sin(time * 1.3 + seed * 3.7)
            let edgeFade = sin(((x - startX) / span) * .pi)
            let opacity = (0.08 + 0.55 * glint) * twinkle * edgeFade

            let moteSize = 1.0 + (seed * 0.37).truncatingRemainder(dividingBy: 1.0) * 1.2
            context.fill(
                Path(ellipseIn: CGRect(x: x - moteSize / 2, y: y - moteSize / 2, width: moteSize, height: moteSize)),
                with: .color(Self.warmWhite.opacity(opacity))
            )
        }
    }

    private func point(from origin: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(cos(angle)) * distance, y: origin.y + CGFloat(sin(angle)) * distance)
    }
}
