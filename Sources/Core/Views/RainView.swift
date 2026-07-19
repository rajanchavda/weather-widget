import SwiftUI

struct RainView: View {
    let width: CGFloat
    let height: CGFloat
    let intensity: RainIntensity
    let freezeDate: Date?

    init(width: CGFloat, height: CGFloat, intensity: RainIntensity, freezeDate: Date? = nil) {
        self.width = width
        self.height = height
        self.intensity = intensity
        self.freezeDate = freezeDate
    }

    enum RainIntensity {
        case drizzle, light, medium, heavy

        var dropCount: Int {
            switch self {
            case .drizzle: return 5
            case .light: return 10
            case .medium: return 25
            case .heavy: return 40
            }
        }

        var baseSpeed: Double {
            switch self {
            case .drizzle: return 2.0
            case .light: return 0.9
            case .medium: return 0.7
            case .heavy: return 0.5
            }
        }

        var baseHeight: Double {
            switch self {
            case .drizzle: return 3.0
            default: return 6.0
            }
        }

        var windSway: Double {
            switch self {
            case .drizzle: return 5.0
            default: return 3.0
            }
        }

        var isThunderstorm: Bool {
            return self == .heavy
        }
    }

    var body: some View {
        if let freezeDate {
            Canvas { context, size in
                render(at: freezeDate.timeIntervalSinceReferenceDate, context: &context, size: size)
            }
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    render(at: timeline.date.timeIntervalSinceReferenceDate, context: &context, size: size)
                }
            }
        }
    }

    private func render(at time: TimeInterval, context: inout GraphicsContext, size: CGSize) {
        if intensity.isThunderstorm {
            let lightningCycle = time.truncatingRemainder(dividingBy: 6.0)
            if lightningCycle < 0.15 {
                let flashOpacity = lightningCycle < 0.08 ? 0.25 : (0.15 - lightningCycle) * 3.5
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flashOpacity)))
            }
        }

        for i in 0..<intensity.dropCount {
            let offset = Double(i) * 0.11

            let layerSeed = (i * 7) % 3
            let depthFactor = layerSeed == 0 ? 1.3 : (layerSeed == 1 ? 1.0 : 0.7)

            let speed = intensity.baseSpeed / depthFactor
            let cycleValue = (time + offset) / speed
            let iteration = Int(floor(cycleValue))
            let progress = cycleValue - Double(iteration)

            let seed = (i &* 12345) &+ (iteration &* 67890)
            let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
            let baseX = randomFactor * Double(size.width)
            let y = progress * (Double(size.height) + 15) - 10

            let slantRatio = intensity.isThunderstorm ? -0.35 : 0.0
            let windDrift = sin(time * 0.3 + Double(i)) * intensity.windSway
            let x = baseX + windDrift + (y * slantRatio)

            let dropWidth = 1.0 * depthFactor
            let dropHeight = (intensity.baseHeight + Double((i * 13) % 6)) * depthFactor
            let dropOpacity = 0.5 + (depthFactor * 0.3)

            if progress < 0.9 {
                let slantX = dropHeight * slantRatio
                let length = sqrt(slantX * slantX + dropHeight * dropHeight)
                let fallAngle = atan2(dropHeight, slantX)
                
                context.drawLayer { ctx in
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(fallAngle - .pi/2))
                    
                    var dropPath = Path()
                    // 4K Realistic Water Droplet Shape (Teardrop)
                    let radius = dropWidth * 0.85
                    
                    dropPath.move(to: CGPoint(x: 0, y: 0)) // Tail
                    dropPath.addQuadCurve(
                        to: CGPoint(x: radius, y: length - radius),
                        control: CGPoint(x: radius * 0.7, y: length * 0.4)
                    )
                    dropPath.addArc(
                        center: CGPoint(x: 0, y: length - radius),
                        radius: radius,
                        startAngle: .degrees(0),
                        endAngle: .degrees(180),
                        clockwise: false
                    )
                    dropPath.addQuadCurve(
                        to: CGPoint(x: 0, y: 0),
                        control: CGPoint(x: -radius * 0.7, y: length * 0.4)
                    )
                    
                    let rainColor = Color(red: 0.6, green: 0.75, blue: 0.95)
                    let gradient = Gradient(colors: [
                        rainColor.opacity(0.0),
                        rainColor.opacity(dropOpacity * 0.6),
                        rainColor.opacity(dropOpacity)
                    ])
                    
                    // Linear gradient simulates realistic 4K motion blur
                    ctx.fill(
                        dropPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: length)
                        )
                    )
                }
            }

            if progress > 0.85 && progress < 1.0 {
                let splashProgress = (progress - 0.85) / 0.15
                let splashY = Double(size.height) - 3
                let splashX = baseX + windDrift + (splashY * slantRatio)

                let splashColor = Color(red: 0.75, green: 0.85, blue: 1.0)
                
                // 1. 3D Perspective Base Ripple (Squashed Ellipse)
                let rippleWidth = 4.0 + splashProgress * 12.0
                let rippleHeight = 1.0 + splashProgress * 3.0
                let rippleOpacity = (1.0 - splashProgress) * dropOpacity * 0.8
                
                // Soft impact glow
                context.fill(
                    Path(ellipseIn: CGRect(x: splashX - rippleWidth/2, y: splashY - rippleHeight/2, width: rippleWidth, height: rippleHeight)),
                    with: .color(splashColor.opacity(rippleOpacity * 0.5))
                )
                
                // Sharp expanding ripple ring
                if splashProgress > 0.1 {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: splashX - rippleWidth/2, y: splashY - rippleHeight/2, width: rippleWidth, height: rippleHeight)),
                        with: .color(splashColor.opacity(rippleOpacity)),
                        lineWidth: 0.8
                    )
                }
                
                // 2. Center Rebounding Droplet ("Crown")
                // Shoots up then decelerates
                let reboundHeight = sin(splashProgress * .pi / 2.0) * 4.5
                let reboundY = splashY - reboundHeight
                let reboundSize = 1.5 * (1.0 - splashProgress * 0.5)
                let reboundOpacity = (1.0 - splashProgress) * dropOpacity
                
                context.fill(
                    Path(ellipseIn: CGRect(x: splashX - reboundSize/2, y: reboundY - reboundSize/2, width: reboundSize, height: reboundSize)),
                    with: .color(splashColor.opacity(reboundOpacity))
                )
                
                // 3. Side Splatter Particles (Foreground drops only)
                if depthFactor > 1.0 {
                    let spreadX = splashProgress * 5.0
                    let spreadY = sin(splashProgress * .pi) * 2.5 // Arcs up and down
                    let particleSize = 1.0
                    let particleOpacity = (1.0 - splashProgress) * dropOpacity * 0.7
                    
                    // Left particle
                    context.fill(
                        Path(ellipseIn: CGRect(x: splashX - spreadX, y: splashY - spreadY, width: particleSize, height: particleSize)),
                        with: .color(splashColor.opacity(particleOpacity))
                    )
                    
                    // Right particle
                    context.fill(
                        Path(ellipseIn: CGRect(x: splashX + spreadX, y: splashY - spreadY, width: particleSize, height: particleSize)),
                        with: .color(splashColor.opacity(particleOpacity))
                    )
                }
            }
        }
    }
}

struct RainDrop: Identifiable {
    let id: Int
    let x: CGFloat
    let delay: Double
    let speed: Double
}
