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
        let flakeCount = 25

        for i in 0..<flakeCount {
            let offset = Double(i) * 0.2
            let speed = 3.0 + Double((i * 17) % 15) / 10.0
            let cycleValue = (time + offset) / speed
            let iteration = Int(floor(cycleValue))
            let progress = cycleValue - Double(iteration)

            let seed = (i &* 12345) &+ (iteration &* 67890)
            let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
            let baseX = randomFactor * Double(size.width)

            let drift = sin((time + offset) * 0.5) * 15.0
            let x = baseX + drift
            let y = progress * (Double(size.height) + 20) - 10

            let flakeSize = 2.0 + Double((i * 23) % 150) / 100.0

            let flakeRect = CGRect(x: x - flakeSize/2, y: y - flakeSize/2, width: flakeSize, height: flakeSize)
            context.fill(Path(ellipseIn: flakeRect), with: .color(.white.opacity(0.8)))
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
