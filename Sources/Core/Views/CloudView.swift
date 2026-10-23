import SwiftUI

struct CloudView: View {
    let width: CGFloat
    let height: CGFloat
    let cover: CloudCover
    let isNight: Bool
    let freezeDate: Date?

    init(width: CGFloat, height: CGFloat, cover: CloudCover, isNight: Bool = false, freezeDate: Date? = nil) {
        self.width = width
        self.height = height
        self.cover = cover
        self.isNight = isNight
        self.freezeDate = freezeDate
    }

    enum CloudCover {
        case few, partly, overcast

        /// WMO 1 (mainly clear), 2 (partly cloudy), 3 (overcast); nil for every other code.
        init?(weatherCode: Int) {
            switch weatherCode {
            case 1: self = .few
            case 2: self = .partly
            case 3: self = .overcast
            default: return nil
            }
        }

        var cloudCount: Int {
            switch self {
            case .few: return 2
            case .partly: return 3
            case .overcast: return 6
            }
        }

        var scale: Double {
            switch self {
            case .few: return 0.7
            case .partly: return 0.9
            case .overcast: return 1.0
            }
        }

        var opacity: Double {
            switch self {
            case .few: return 0.5
            case .partly: return 0.65
            case .overcast: return 0.75
            }
        }

        /// Top, middle and underside of each cloud. Overcast is grayer, and night is dim and cool
        /// so clouds don't glow white against the dark sky.
        func gradientColors(isNight: Bool) -> [Color] {
            switch (self, isNight) {
            case (.overcast, false):
                return [
                    Color(red: 0.78, green: 0.80, blue: 0.84),
                    Color(red: 0.62, green: 0.65, blue: 0.71),
                    Color(red: 0.42, green: 0.45, blue: 0.53)
                ]
            case (.overcast, true):
                return [
                    Color(red: 0.32, green: 0.35, blue: 0.45),
                    Color(red: 0.22, green: 0.25, blue: 0.34),
                    Color(red: 0.12, green: 0.14, blue: 0.21)
                ]
            case (_, false):
                return [
                    Color.white,
                    Color(red: 0.85, green: 0.88, blue: 0.92),
                    Color(red: 0.60, green: 0.65, blue: 0.75)
                ]
            case (_, true):
                return [
                    Color(red: 0.45, green: 0.49, blue: 0.62),
                    Color(red: 0.33, green: 0.37, blue: 0.50),
                    Color(red: 0.20, green: 0.23, blue: 0.33)
                ]
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

        // Every n-th cloud keeps the subset spread evenly across the bar.
        let spacing = max(1, clouds.count / cover.cloudCount)
        let visibleClouds = clouds.enumerated().filter { $0.offset % spacing == 0 }.prefix(cover.cloudCount).map(\.element)
        let cloudGradient = Gradient(colors: cover.gradientColors(isNight: isNight))

        for cloud in visibleClouds {
            let adjustedTime = time + cloud.delay
            let positiveTime = adjustedTime > 0 ? adjustedTime : adjustedTime + 1000000.0
            let cycle = positiveTime.truncatingRemainder(dividingBy: cloud.duration)
            let progress = cycle / cloud.duration

            let baseScale = Double(size.height) / 300.0
            let actualScale = cloud.scale * cover.scale * baseScale

            let startX = -220.0 * actualScale
            let endX = Double(size.width) + 220.0 * actualScale
            let distance = endX - startX

            let x = startX + progress * distance
            let y = cloud.top * Double(size.height)

            context.drawLayer { ctx in
                ctx.translateBy(x: x, y: y)
                ctx.scaleBy(x: actualScale, y: actualScale)
                ctx.opacity = cloud.opacity * cover.opacity

                var cloudPath = Path()
                cloudPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 220, height: 70), cornerSize: CGSize(width: 35, height: 35))
                cloudPath.addEllipse(in: CGRect(x: 28, y: -42, width: 90, height: 90))
                cloudPath.addEllipse(in: CGRect(x: 78, y: -58, width: 110, height: 110))

                ctx.addFilter(.shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 6))

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
