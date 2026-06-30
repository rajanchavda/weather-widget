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
        let sunX = (size.width / 2.0) + 140.0
        let sunY = size.height / 2.0
        let center = CGPoint(x: sunX, y: sunY)

        let rayCount = 12
        for i in 0..<rayCount {
            let angleOffset = (Double.pi * 2.0 / Double(rayCount)) * Double(i)
            let rotation = time * 0.15 + angleOffset

            var path = Path()
            path.move(to: center)

            let rayLength: CGFloat = 35.0
            let angle1 = CGFloat(rotation - 0.05)
            let angle2 = CGFloat(rotation + 0.05)

            path.addLine(to: CGPoint(x: center.x + cos(angle1) * rayLength, y: center.y + sin(angle1) * rayLength))
            path.addLine(to: CGPoint(x: center.x + cos(angle2) * rayLength, y: center.y + sin(angle2) * rayLength))
            path.closeSubpath()

            context.fill(path, with: .color(.white.opacity(0.12)))
        }

        let pulse = sin(time * 2.0) * 0.1 + 0.9
        let haloSize = 28.0 * pulse
        context.fill(Path(ellipseIn: CGRect(x: center.x - haloSize/2, y: center.y - haloSize/2, width: haloSize, height: haloSize)), with: .color(.yellow.opacity(0.4)))

        let coreSize = 14.0
        context.fill(Path(ellipseIn: CGRect(x: center.x - coreSize/2, y: center.y - coreSize/2, width: coreSize, height: coreSize)), with: .color(.white.opacity(0.95)))

        let flareShiftX = sin(time * 0.4) * 25.0
        let flareShiftY = cos(time * 0.3) * 5.0
        let flareCenter = CGPoint(x: center.x + flareShiftX, y: center.y + flareShiftY)

        let hFlareWidth = 150.0 + sin(time) * 10.0
        let hFlareHeight = 1.5
        context.fill(Path(ellipseIn: CGRect(x: flareCenter.x - hFlareWidth/2, y: flareCenter.y - hFlareHeight/2, width: hFlareWidth, height: hFlareHeight)), with: .color(Color(red: 0.8, green: 0.9, blue: 1.0).opacity(0.4)))

        let hFlareWidth2 = 80.0
        let hFlareHeight2 = 3.0
        context.fill(Path(ellipseIn: CGRect(x: flareCenter.x - hFlareWidth2/2, y: flareCenter.y - hFlareHeight2/2, width: hFlareWidth2, height: hFlareHeight2)), with: .color(.white.opacity(0.3)))

        context.drawLayer { ctx in
            ctx.translateBy(x: flareCenter.x, y: flareCenter.y)
            ctx.rotate(by: .degrees(25))
            ctx.fill(Path(ellipseIn: CGRect(x: -40, y: -0.5, width: 80, height: 1.0)), with: .color(.orange.opacity(0.3)))
        }

        context.drawLayer { ctx in
            ctx.translateBy(x: flareCenter.x, y: flareCenter.y)
            ctx.rotate(by: .degrees(-15))
            ctx.fill(Path(ellipseIn: CGRect(x: -60, y: -0.5, width: 120, height: 1.0)), with: .color(.yellow.opacity(0.2)))
        }

        let ghost1X = center.x - flareShiftX * 1.5 - 30.0
        let ghost1Y = center.y - flareShiftY * 1.5
        context.fill(Path(ellipseIn: CGRect(x: ghost1X - 4, y: ghost1Y - 4, width: 8, height: 8)), with: .color(Color(red: 0.5, green: 0.8, blue: 1.0).opacity(0.2)))
        context.stroke(Path(ellipseIn: CGRect(x: ghost1X - 4, y: ghost1Y - 4, width: 8, height: 8)), with: .color(Color(red: 0.5, green: 0.8, blue: 1.0).opacity(0.3)), lineWidth: 0.5)

        let ghost2X = center.x - flareShiftX * 2.2 - 60.0
        let ghost2Y = center.y - flareShiftY * 2.2
        context.fill(Path(ellipseIn: CGRect(x: ghost2X - 2.5, y: ghost2Y - 2.5, width: 5, height: 5)), with: .color(.green.opacity(0.15)))

        let ghost3X = center.x - flareShiftX * 0.8 + 20.0
        let ghost3Y = center.y - flareShiftY * 0.8
        context.fill(Path(ellipseIn: CGRect(x: ghost3X - 6, y: ghost3Y - 6, width: 12, height: 12)), with: .color(.orange.opacity(0.1)))

        let dustCount = 15
        for i in 0..<dustCount {
            let offset = Double(i) * 0.5
            let speed = 0.4 + Double(i % 4) * 0.1
            let cycle = (time * speed + offset).truncatingRemainder(dividingBy: 15.0)
            let progress = cycle / 15.0

            let baseX = (Double(i) * 123.0).truncatingRemainder(dividingBy: Double(size.width))
            let x = baseX + progress * 80.0

            let yDrift = sin(time * 0.3 + Double(i)) * 4.0
            let y = Double(size.height / 2) + yDrift

            let dustOpacity = sin(progress * .pi) * 0.35
            let dustSize = 1.5 + Double(i % 3)

            let dustColor = i % 2 == 0 ? Color.white : Color.yellow

            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dustSize, height: dustSize)), with: .color(dustColor.opacity(dustOpacity)))
        }
    }
}
