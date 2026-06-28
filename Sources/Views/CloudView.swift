import SwiftUI

struct CloudView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                let clouds: [(top: Double, scale: Double, duration: Double, delay: Double, opacity: Double)] = [
                    (0.12, 0.8, 140, -8, 0.9),
                    (0.22, 1.1, 180, -20, 0.85),
                    (0.38, 0.6, 112, -5, 0.7),
                    (0.48, 1.3, 220, -35, 0.95),
                    (0.65, 0.9, 160, -15, 0.8),
                    (0.78, 0.5, 100, -2, 0.65)
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
                        ctx.opacity = cloud.opacity * 0.45

                        var cloudPath = Path()
                        cloudPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 220, height: 70), cornerSize: CGSize(width: 35, height: 35))
                        cloudPath.addEllipse(in: CGRect(x: 28, y: -42, width: 90, height: 90))
                        cloudPath.addEllipse(in: CGRect(x: 78, y: -58, width: 110, height: 110))

                        ctx.addFilter(.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4))
                        ctx.fill(cloudPath, with: .color(.white))
                    }
                }
            }
        }
    }
}
