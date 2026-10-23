import SwiftUI

struct SnowView: View {
    let width: CGFloat
    let height: CGFloat
    let intensity: SnowIntensity
    let freezeDate: Date?

    init(width: CGFloat, height: CGFloat, intensity: SnowIntensity, freezeDate: Date? = nil) {
        self.width = width
        self.height = height
        self.intensity = intensity
        self.freezeDate = freezeDate
    }

    enum SnowIntensity {
        case light, moderate, heavy

        /// WMO 71/77/85 (slight snow, snow grains, slight showers), 73 (moderate), 75/86 (heavy); nil otherwise.
        init?(weatherCode: Int) {
            switch weatherCode {
            case 71, 77, 85: self = .light
            case 73: self = .moderate
            case 75, 86: self = .heavy
            default: return nil
            }
        }

        var flakeCount: Int {
            switch self {
            case .light: return 18
            case .moderate: return 35
            case .heavy: return 60
            }
        }

        /// Seconds for a mid-layer flake to cross the bar, before per-flake variation.
        var baseSpeed: Double {
            switch self {
            case .light: return 5.0
            case .moderate: return 4.0
            case .heavy: return 3.2
            }
        }

        /// Horizontal drift in points per second for the mid layer.
        var windDrift: Double {
            switch self {
            case .light: return 6.0
            case .moderate: return 8.0
            case .heavy: return 14.0
            }
        }

        var frostHeight: Double {
            switch self {
            case .light: return 2.0
            case .moderate: return 3.0
            case .heavy: return 4.0
            }
        }
    }

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
        for i in 0..<intensity.flakeCount {
            // Depth Layering (3D Parallax)
            let layerSeed = (i * 7) % 3
            let depthFactor = layerSeed == 0 ? 1.5 : (layerSeed == 1 ? 1.0 : 0.6)

            let offset = Double(i) * 0.2
            let baseSpeed = intensity.baseSpeed + Double((i * 17) % 15) / 10.0
            let speed = baseSpeed / depthFactor // Foreground falls faster
            
            let cycleValue = (time + offset) / speed
            let iteration = Int(floor(cycleValue))
            let progress = cycleValue - Double(iteration)

            let seed = (i &* 12345) &+ (iteration &* 67890)
            let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
            let baseX = randomFactor * (Double(size.width) + 40.0) - 20.0 // Allow spawning off-screen

            // Complex flutter physics (like a falling leaf)
            let flutterPhase = time * (1.2 + Double(i % 3) * 0.5) + Double(i)
            let flutterAmplitude = 6.0 * depthFactor
            let flutter = sin(flutterPhase) * flutterAmplitude
            
            // Gentle continuous wind drift
            let windDrift = time * intensity.windDrift * depthFactor
            let rawX = baseX + flutter + windDrift
            
            // Wrap around seamlessly
            let x = rawX.truncatingRemainder(dividingBy: Double(size.width) + 40.0) - 20.0
            let y = progress * (Double(size.height) + 20) - 10

            let baseFlakeSize = 1.5 + Double((i * 23) % 150) / 100.0
            let flakeSize = baseFlakeSize * depthFactor

            // Fade in and out
            let fadeOpacity: Double
            if progress < 0.15 {
                fadeOpacity = progress / 0.15
            } else if progress > 0.85 {
                fadeOpacity = (1.0 - progress) / 0.15
            } else {
                fadeOpacity = 1.0
            }
            
            let layerOpacity = depthFactor > 1.2 ? 0.6 : (depthFactor > 0.8 ? 0.85 : 0.4)
            let finalOpacity = fadeOpacity * layerOpacity

            let flakeRect = CGRect(x: x - flakeSize/2, y: y - flakeSize/2, width: flakeSize, height: flakeSize)
            
            if depthFactor > 1.2 {
                // Foreground flakes get a slight blur/glow effect
                context.fill(Path(ellipseIn: flakeRect), with: .color(.white.opacity(finalOpacity * 0.5)))
                let coreRect = flakeRect.insetBy(dx: flakeSize * 0.2, dy: flakeSize * 0.2)
                context.fill(Path(ellipseIn: coreRect), with: .color(.white.opacity(finalOpacity)))
            } else {
                context.fill(Path(ellipseIn: flakeRect), with: .color(.white.opacity(finalOpacity)))
            }
        }
        
        // Snow Accumulation Frost at the bottom
        let pileHeight = intensity.frostHeight
        let pileRect = CGRect(x: 0, y: Double(size.height) - pileHeight, width: Double(size.width), height: pileHeight)
        let pileGradient = Gradient(colors: [.white.opacity(0.0), .white.opacity(0.4)])
        
        context.fill(
            Path(pileRect),
            with: .linearGradient(
                pileGradient,
                startPoint: CGPoint(x: 0, y: Double(size.height) - pileHeight),
                endPoint: CGPoint(x: 0, y: Double(size.height))
            )
        )
    }
}

struct Snowflake: Identifiable {
    let id: Int
    let x: CGFloat
    let size: CGFloat
    let speed: Double
    let delay: Double
    let drift: CGFloat
}
