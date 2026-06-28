import SwiftUI

struct FogView: View {
    let width: CGFloat
    let height: CGFloat
    let isNight: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                let fogColor = isNight ? Color(red: 0.82, green: 0.88, blue: 0.96) : Color(red: 0.98, green: 0.98, blue: 0.96)
                let wispCount = 8

                for i in 0..<wispCount {
                    let layer = i % 3

                    let speedFactor: Double
                    let opacityFactor: Double
                    let heightFactor: Double
                    let yOffset: Double

                    switch layer {
                    case 0:
                        speedFactor = 5.0
                        opacityFactor = 0.38
                        heightFactor = 0.9
                        yOffset = -2.0
                    case 1:
                        speedFactor = 10.0
                        opacityFactor = 0.55
                        heightFactor = 1.2
                        yOffset = 0.0
                    default:
                        speedFactor = 15.0
                        opacityFactor = 0.70
                        heightFactor = 1.5
                        yOffset = 2.0
                    }

                    let individualSpeed = speedFactor + Double((i * 3) % 5)
                    let wispWidth = (250.0 + Double((i * 17) % 4) * 40.0) * heightFactor
                    let wispHeight = (16.0 + Double((i * 11) % 3) * 4.0) * heightFactor

                    let totalSpan = Double(size.width) + wispWidth
                    let startX = Double(i) * (Double(size.width) / Double(wispCount))
                    let rawX = startX + time * individualSpeed
                    let x = rawX.truncatingRemainder(dividingBy: totalSpan) - wispWidth

                    let rollSpeed = 0.3 + Double(i % 3) * 0.15
                    let rollAmplitude = 2.5 * heightFactor
                    let yOscillation = sin(time * rollSpeed + Double(i)) * rollAmplitude
                    let y = Double(size.height / 2.0) - (wispHeight / 2.0) + yOffset + yOscillation

                    let pulse = 0.85 + sin(time * 0.4 + Double(i)) * 0.15
                    let currentOpacity = opacityFactor * pulse

                    let rect = CGRect(x: x, y: y, width: wispWidth, height: wispHeight)
                    context.fill(Path(ellipseIn: rect), with: .color(fogColor.opacity(currentOpacity)))
                }
            }
            .blur(radius: 6.0)
        }
    }
}
