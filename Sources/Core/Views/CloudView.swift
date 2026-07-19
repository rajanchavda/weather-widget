import SwiftUI

struct CloudView: View {
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
        // (top, scale, duration, delay, opacity)
        // Delay is calculated to spread them evenly at startup (progress = i / 6.0)
        let clouds: [(top: Double, scale: Double, duration: Double, delay: Double, opacity: Double)] = [
            (0.12, 0.8, 140, 0.0, 0.9),    // 0% across
            (0.22, 1.1, 180, 30.0, 0.85),  // ~16% across
            (0.38, 0.6, 112, 37.0, 0.7),   // ~33% across
            (0.48, 1.3, 220, 110.0, 0.95), // 50% across
            (0.65, 0.9, 160, 106.0, 0.8),  // ~66% across
            (0.78, 0.5, 100, 83.0, 0.65)   // ~83% across
        ]

        for cloud in clouds {
            let adjustedTime = time + cloud.delay
            let positiveTime = adjustedTime > 0 ? adjustedTime : adjustedTime + 1000000.0
            let cycle = positiveTime.truncatingRemainder(dividingBy: cloud.duration)
            let progress = cycle / cloud.duration

            let baseScale = Double(size.height) / 300.0
            let actualScale = cloud.scale * baseScale

            let startX = -220.0 * actualScale
            let endX = Double(size.width) + 220.0 * actualScale
            let distance = endX - startX

            let x = startX + progress * distance
            let y = cloud.top * Double(size.height)

            context.drawLayer { ctx in
                ctx.translateBy(x: x, y: y)
                ctx.scaleBy(x: actualScale, y: actualScale)
                ctx.opacity = cloud.opacity * 0.7

                var cloudPath = Path()
                cloudPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 220, height: 70), cornerSize: CGSize(width: 35, height: 35))
                cloudPath.addEllipse(in: CGRect(x: 28, y: -42, width: 90, height: 90))
                cloudPath.addEllipse(in: CGRect(x: 78, y: -58, width: 110, height: 110))

                ctx.addFilter(.shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 6))
                
                let cloudGradient = Gradient(colors: [
                    Color.white,
                    Color(red: 0.85, green: 0.88, blue: 0.92), // Mid-tone
                    Color(red: 0.60, green: 0.65, blue: 0.75) // Deep cool shadow at the bottom
                ])
                
                ctx.fill(
                    cloudPath,
                    with: .linearGradient(
                        cloudGradient,
                        startPoint: CGPoint(x: 0, y: -60),
                        endPoint: CGPoint(x: 0, y: 70)
                    )
                )
            }
        }
    }
}
