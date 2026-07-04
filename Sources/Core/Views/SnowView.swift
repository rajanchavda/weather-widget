import SwiftUI

struct SnowView: View {
    let width: CGFloat
    let height: CGFloat
    let freezeDate: Date?

    init(width: CGFloat, height: CGFloat, freezeDate: Date? = nil) {
        self.width = width
        self.height = height
        self.freezeDate = freezeDate
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
        let flakeCount = 35

        for i in 0..<flakeCount {
            // Depth Layering (3D Parallax)
            let layerSeed = (i * 7) % 3
            let depthFactor = layerSeed == 0 ? 1.5 : (layerSeed == 1 ? 1.0 : 0.6)

            let offset = Double(i) * 0.2
            let baseSpeed = 4.0 + Double((i * 17) % 15) / 10.0
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
            let windDrift = time * 8.0 * depthFactor
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
        let pileHeight = 3.0
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
