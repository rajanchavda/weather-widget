import SwiftUI

struct StarsView: View {
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
        let starCount = Int(size.width / 25)

        for i in 0..<starCount {
            let seed1 = (i &* 1103515245) &+ 12345
            let seed2 = (seed1 &* 1103515245) &+ 12345
            let seed3 = (seed2 &* 1103515245) &+ 12345

            let randX = Double((seed1 ^ (seed1 >> 16)) & 0xFFFF) / 65535.0
            let randY = Double((seed2 ^ (seed2 >> 16)) & 0xFFFF) / 65535.0
            let randZ = Double((seed3 ^ (seed3 >> 16)) & 0xFFFF) / 65535.0

            let x = randX * Double(size.width)
            let y = randY * Double(size.height)
            let starSize = 0.8 + (randZ * 1.2)

            let twinkleSpeed = 0.5 + (Double(i % 10) / 10.0) * 1.5
            let twinklePhase = Double(i) * 0.5
            let currentOpacity = 0.2 + ((sin(time * twinkleSpeed + twinklePhase) + 1.0) / 2.0) * 0.8

            let colorSeed = i % 10
            let starColor: Color
            if colorSeed == 0 {
                starColor = Color(red: 0.7, green: 0.85, blue: 1.0)
            } else if colorSeed == 1 {
                starColor = Color(red: 1.0, green: 0.95, blue: 0.8)
            } else {
                starColor = .white
            }

            let starRect = CGRect(x: x, y: y, width: starSize, height: starSize)
            context.fill(Path(ellipseIn: starRect), with: .color(starColor.opacity(currentOpacity)))
        }

        let shootingStarCycle = 15.0
        let cycleTime = time.truncatingRemainder(dividingBy: shootingStarCycle)

        if cycleTime < 0.6 {
            let progress = cycleTime / 0.6
            let globalCycle = Int(time / shootingStarCycle)

            let seed1 = (globalCycle &* 1103515245) &+ 12345
            let seed2 = (seed1 &* 1103515245) &+ 12345

            let randY = Double((seed1 ^ (seed1 >> 16)) & 0xFFFF) / 65535.0
            let randX = Double((seed2 ^ (seed2 >> 16)) & 0xFFFF) / 65535.0

            let startY = randY * Double(size.height * 0.5)
            let startX = Double(size.width) * (0.4 + randX * 0.7)

            let distance = 250.0
            let currentX = startX - (progress * distance)
            let currentY = startY + (progress * distance * 0.25)

            let streakLength = 35.0 * (1.0 - abs(progress - 0.5) * 2.0)
            var path = Path()
            path.move(to: CGPoint(x: currentX, y: currentY))
            path.addLine(to: CGPoint(x: currentX + streakLength, y: currentY - streakLength * 0.25))

            let opacity = progress < 0.5 ? progress * 2.0 : (1.0 - progress) * 2.0

            context.stroke(path, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: currentX - 1.0, y: currentY - 1.0, width: 2, height: 2)), with: .color(.white.opacity(opacity)))
        }
    }
}
