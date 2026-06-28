import SwiftUI

struct RainView: View {
    let width: CGFloat
    let height: CGFloat
    let intensity: RainIntensity

    enum RainIntensity {
        case light, medium, heavy

        var dropCount: Int {
            switch self {
            case .light: return 15
            case .medium: return 25
            case .heavy: return 40
            }
        }

        var baseSpeed: Double {
            switch self {
            case .light: return 0.9
            case .medium: return 0.7
            case .heavy: return 0.5
            }
        }

        var isThunderstorm: Bool {
            return self == .heavy
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                if intensity.isThunderstorm {
                    let lightningCycle = time.truncatingRemainder(dividingBy: 6.0)
                    if lightningCycle < 0.15 {
                        let flashOpacity = lightningCycle < 0.08 ? 0.25 : (0.15 - lightningCycle) * 3.5
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flashOpacity)))
                    }
                }

                for i in 0..<intensity.dropCount {
                    let offset = Double(i) * 0.11

                    let layerSeed = (i * 7) % 3
                    let depthFactor = layerSeed == 0 ? 1.3 : (layerSeed == 1 ? 1.0 : 0.7)

                    let speed = intensity.baseSpeed / depthFactor
                    let cycleValue = (time + offset) / speed
                    let iteration = Int(floor(cycleValue))
                    let progress = cycleValue - Double(iteration)

                    let seed = (i &* 12345) &+ (iteration &* 67890)
                    let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
                    let baseX = randomFactor * Double(size.width)
                    let y = progress * (Double(size.height) + 15) - 10

                    let slantRatio = intensity.isThunderstorm ? -0.35 : 0.0
                    let windDrift = sin(time * 0.3 + Double(i)) * 3.0
                    let x = baseX + windDrift + (y * slantRatio)

                    let dropWidth = 1.0 * depthFactor
                    let dropHeight = (8.0 + Double((i * 13) % 6)) * depthFactor
                    let dropOpacity = 0.5 + (depthFactor * 0.3)

                    if progress < 0.9 {
                        var dropPath = Path()
                        let slantX = dropHeight * slantRatio
                        dropPath.move(to: CGPoint(x: x, y: y))
                        dropPath.addLine(to: CGPoint(x: x + slantX, y: y + dropHeight))

                        let rainColor = Color(red: 0.6, green: 0.75, blue: 0.95)
                        context.stroke(
                            dropPath,
                            with: .color(rainColor.opacity(dropOpacity)),
                            style: StrokeStyle(lineWidth: dropWidth, lineCap: .round)
                        )
                    }

                    if progress > 0.85 && progress < 1.0 {
                        let splashProgress = (progress - 0.85) / 0.15
                        let splashY = Double(size.height) - 3
                        let splashX = baseX + windDrift + (splashY * slantRatio)

                        let splashColor = Color(red: 0.65, green: 0.8, blue: 1.0)

                        let splash1Size = 3.0 + splashProgress * 5.0
                        let splash1Opacity = (1.0 - splashProgress) * dropOpacity * 0.6
                        context.fill(
                            Path(ellipseIn: CGRect(x: splashX - splash1Size/2, y: splashY - splash1Size/2, width: splash1Size, height: splash1Size)),
                            with: .color(splashColor.opacity(splash1Opacity))
                        )

                        if depthFactor > 0.9 && splashProgress > 0.3 {
                            let rippleSize = 5.0 + (splashProgress - 0.3) * 6.0
                            let rippleOpacity = (1.0 - splashProgress) * 0.3
                            context.stroke(
                                Path(ellipseIn: CGRect(x: splashX - rippleSize/2, y: splashY - rippleSize/2, width: rippleSize, height: rippleSize)),
                                with: .color(splashColor.opacity(rippleOpacity)),
                                lineWidth: 0.8
                            )
                        }
                    }
                }
            }
        }
    }
}

struct RainDrop: Identifiable {
    let id: Int
    let x: CGFloat
    let delay: Double
    let speed: Double
}
