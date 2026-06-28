import SwiftUI

struct SnowView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                let flakeCount = 25

                for i in 0..<flakeCount {
                    let offset = Double(i) * 0.2
                    let speed = 3.0 + Double((i * 17) % 15) / 10.0
                    let cycleValue = (time + offset) / speed
                    let iteration = Int(floor(cycleValue))
                    let progress = cycleValue - Double(iteration)

                    let seed = (i &* 12345) &+ (iteration &* 67890)
                    let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
                    let baseX = randomFactor * Double(width)

                    let drift = sin((time + offset) * 0.5) * 15.0
                    let x = baseX + drift
                    let y = progress * (Double(height) + 20) - 10

                    let size = 2.0 + Double((i * 23) % 150) / 100.0

                    let flakeRect = CGRect(x: x - size/2, y: y - size/2, width: size, height: size)
                    context.fill(Path(ellipseIn: flakeRect), with: .color(.white.opacity(0.8)))
                }
            }
        }
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
