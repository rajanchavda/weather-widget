import SwiftUI

// Display settings that will be controlled from the menu bar status item
class OverlaySettings: ObservableObject {
    @Published var showAurora: Bool = true
    @Published var showBottomLine: Bool = false
    @Published var selectedUnit: WeatherUnit = .celsius
    @Published var brightness: Double = 1.0 // 0.0 to 1.0
    @Published var manualWeatherCode: Int? = nil // nil = auto (use real weather)
    @Published var manualIsNight: Bool? = nil    // nil = auto

    enum WeatherUnit: String, CaseIterable {
        case celsius = "°C"
        case fahrenheit = "°F"
    }

    enum AuroraStyle: String, CaseIterable {
        case auto = "Auto (Weather-based)"
        case clearDay = "Clear Day"
        case clearNight = "Clear Night"
        case cloudy = "Cloudy"
        case fog = "Foggy"
        case rain = "Rainy"
        case snow = "Snowy"
        case thunderstorm = "Thunderstorm"

        var weatherCode: Int? {
            switch self {
            case .auto: return nil
            case .clearDay: return 0
            case .clearNight: return 0
            case .cloudy: return 3
            case .fog: return 45
            case .rain: return 61
            case .snow: return 73
            case .thunderstorm: return 95
            }
        }

        var forceNight: Bool {
            return self == .clearNight
        }
    }
}

struct OverlayView: View {
    @ObservedObject var weatherManager: WeatherManager
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 1. Atmospheric Aurora Background
                if settings.showAurora {
                    auroraView
                        .transition(.opacity)

                    // Stars for clear night sky
                    if shouldShowStars() {
                        starsView(width: geometry.size.width, height: geometry.size.height)
                    }

                    // Weather particles
                    let code = getEffectiveWeatherCode()

                    // Sun for clear day
                    if (code == 0 || code == 1) && !checkIsNight() {
                        SunView(width: geometry.size.width, height: geometry.size.height)
                            .id("sun-\(code)")
                    }

                    // Clouds animation for cloudy weather
                    if code == 2 || code == 3 {
                        CloudView(width: geometry.size.width, height: geometry.size.height)
                            .id("clouds-\(code)")
                    }

                    // Fog animation

                    if code == 45 || code == 48 {
                        FogView(width: geometry.size.width, height: geometry.size.height)
                            .id("fog-\(code)")
                    }

                    // Rain animation (light rain)
                    if code >= 51 && code <= 67 {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .light)
                            .id("rain-light-\(code)")
                    }

                    // Showers (medium rain)
                    if code >= 80 && code <= 82 {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .medium)
                            .id("rain-medium-\(code)")
                    }

                    // Thunderstorm (heavy continuous rain)
                    if code >= 95 && code <= 99 {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .heavy)
                            .id("rain-heavy-\(code)")
                    }

                    // Snow animation
                    if (code >= 71 && code <= 77) || (code >= 85 && code <= 86) {
                        SnowView(width: geometry.size.width, height: geometry.size.height)
                            .id("snow-\(code)")
                    }
                }

                // 2. Sleek Bottom Temperature Forecast Line
                if settings.showBottomLine && weatherManager.hourlyTemps.count >= 12 {
                    temperatureLineView(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .opacity(settings.brightness)
        }
        .animation(.easeInOut(duration: 0.8), value: weatherManager.weatherCode)
        .animation(.easeInOut(duration: 0.5), value: settings.showAurora)
        .animation(.easeInOut(duration: 0.5), value: settings.showBottomLine)
        .animation(.easeInOut(duration: 0.3), value: settings.brightness)
        .animation(.easeInOut(duration: 0.5), value: settings.manualWeatherCode)
    }
    
    // MARK: - Aurora (Ambient background gradient)
    private var auroraView: some View {
        let colors = getAuroraColors()
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Stars (Clear night sky)
    private func starsView(width: CGFloat, height: CGFloat) -> some View {
        let starPositions = generateStarPositions(width: width, height: height)

        return ZStack {
            ForEach(0..<starPositions.count, id: \.self) { index in
                let pos = starPositions[index]
                Circle()
                    .fill(Color.white.opacity(pos.opacity))
                    .frame(width: pos.size, height: pos.size)
                    .position(x: pos.x, y: pos.y)
                    .animation(
                        Animation.easeInOut(duration: pos.twinkleDuration)
                            .repeatForever(autoreverses: true)
                            .delay(pos.delay),
                        value: settings.showAurora
                    )
            }
        }
    }

    private func generateStarPositions(width: CGFloat, height: CGFloat) -> [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double, twinkleDuration: Double, delay: Double)] {
        var positions: [(CGFloat, CGFloat, CGFloat, Double, Double, Double)] = []
        let starCount = Int(width / 25) // Roughly 1 star per 25 pixels width (4x more stars)

        // Use a deterministic seed based on screen width for consistent star positions
        var pseudoRandom = Int(width * 1000)
        func nextRandom() -> Int {
            pseudoRandom = (pseudoRandom &* 1103515245 &+ 12345) & 0x7fffffff
            return pseudoRandom
        }

        for _ in 0..<starCount {
            let x = CGFloat(nextRandom() % Int(width))
            let y = CGFloat(nextRandom() % Int(height))
            let size = CGFloat(0.8 + Double(nextRandom() % 120) / 100.0) // 0.8-2px (smaller variance)
            let opacity = 0.4 + Double(nextRandom() % 60) / 100.0 // 0.4-1.0
            let twinkleDuration = 1.2 + Double(nextRandom() % 350) / 100.0 // 1.2-4.7s
            let delay = Double(nextRandom() % 300) / 100.0 // 0-3s

            positions.append((x, y, size, opacity, twinkleDuration, delay))
        }

        return positions
    }
    
    // MARK: - Temperature Forecast Line
    private func temperatureLineView(width: CGFloat, height: CGFloat) -> some View {
        let temps = weatherManager.hourlyTemps
        let minTemp = temps.min() ?? 0.0
        let maxTemp = temps.max() ?? 100.0
        let tempRange = max(maxTemp - minTemp, 1.0) // Avoid division by zero
        
        // Define color gradient representing the 12 forecast temperatures
        let lineGradient = LinearGradient(
            colors: temps.map { getTemperatureColor($0) },
            startPoint: .leading,
            endPoint: .trailing
        )
        
        return Path { path in
            let stepX = width / CGFloat(temps.count - 1)
            
            for i in 0..<temps.count {
                let x = CGFloat(i) * stepX
                
                // Normalize temp to a y-offset within the bottom 6px of the menu bar
                // High temp is at the top of our 6px drawing zone, low temp at the very bottom
                let normalizedTemp = (temps[i] - minTemp) / tempRange
                let yOffset = CGFloat(normalizedTemp) * 4.0 // Scale variation to 4px
                let y = height - 1.0 - yOffset // Draw in the bottom zone (1px to 5px from bottom)
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            lineGradient,
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Color Mapping Helpers
    
    private func getTemperatureColor(_ tempC: Double) -> Color {
        // We convert to Celsius internally for uniform mapping logic
        let temp = tempC
        if temp < 0 {
            return Color(red: 0.0, green: 0.8, blue: 1.0) // Deep Cyan (Freezing)
        } else if temp < 15 {
            return Color(red: 0.2, green: 0.6, blue: 0.9) // Cool Blue
        } else if temp < 22 {
            return Color(red: 0.3, green: 0.8, blue: 0.5) // Mild Green/Teal
        } else if temp < 30 {
            return Color(red: 0.95, green: 0.7, blue: 0.1) // Warm Gold/Yellow
        } else {
            return Color(red: 0.9, green: 0.2, blue: 0.1) // Hot Red/Orange
        }
    }
    
    private func getAuroraColors() -> [Color] {
        let code = settings.manualWeatherCode ?? weatherManager.weatherCode
        let isNight = checkIsNight()

        switch code {
        case 0, 1: // Clear
            if isNight {
                return [Color.indigo.opacity(0.12), Color.purple.opacity(0.08), Color.clear]
            } else {
                return [Color.orange.opacity(0.12), Color.yellow.opacity(0.08), Color.clear]
            }
        case 2, 3: // Cloudy
            return [Color.gray.opacity(0.22), Color(white: 0.7).opacity(0.15), Color.blue.opacity(0.08), Color.clear]
        case 45, 48: // Fog
            return [
                Color.white.opacity(0.35),
                Color(white: 0.85).opacity(0.25),
                Color.white.opacity(0.15),
                Color.clear
            ]
        case 51...67, 80...82: // Rain / Drizzle
            return [Color.blue.opacity(0.14), Color.purple.opacity(0.08), Color.clear]
        case 71...77, 85...86: // Snow
            return [Color.white.opacity(0.2), Color.cyan.opacity(0.08), Color.clear]
        case 95...99: // Thunderstorm
            return [Color(red: 0.1, green: 0.05, blue: 0.2).opacity(0.18), Color.purple.opacity(0.05), Color.clear]
        default:
            return [Color.blue.opacity(0.1), Color.clear]
        }
    }

    private func checkIsNight() -> Bool {
        if let manualIsNight = settings.manualIsNight {
            return manualIsNight
        }
        return weatherManager.isNight
    }

    private func getEffectiveWeatherCode() -> Int {
        return settings.manualWeatherCode ?? weatherManager.weatherCode
    }

    private func shouldShowStars() -> Bool {
        let code = getEffectiveWeatherCode()
        return checkIsNight() && (code == 0 || code == 1)
    }
}

// MARK: - Rain Animation

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

                // Lightning flash for thunderstorms (every 4-8 seconds)
                if intensity.isThunderstorm {
                    let lightningCycle = time.truncatingRemainder(dividingBy: 6.0)
                    if lightningCycle < 0.15 {
                        let flashOpacity = lightningCycle < 0.08 ? 0.25 : (0.15 - lightningCycle) * 3.5
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flashOpacity)))
                    }
                }

                for i in 0..<intensity.dropCount {
                    let offset = Double(i) * 0.11

                    // Create depth layers (3 layers: near, mid, far)
                    let layerSeed = (i * 7) % 3
                    let depthFactor = layerSeed == 0 ? 1.3 : (layerSeed == 1 ? 1.0 : 0.7)

                    // Speed varies by depth (closer = faster)
                    let speed = intensity.baseSpeed / depthFactor
                    let cycleValue = (time + offset) / speed
                    let iteration = Int(floor(cycleValue))
                    let progress = cycleValue - Double(iteration)

                    // Horizontal position with slight wind drift (randomized per iteration)
                    let seed = (i &* 12345) &+ (iteration &* 67890)
                    let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
                    let baseX = randomFactor * Double(size.width)
                    let windDrift = sin(time * 0.3 + Double(i)) * 3.0
                    let x = baseX + windDrift

                    // Vertical position
                    let y = progress * (Double(size.height) + 15) - 10

                    // Drop properties based on depth
                    let dropWidth = 1.0 * depthFactor // Thinner drops
                    let dropHeight = (8.0 + Double((i * 13) % 6)) * depthFactor // 8-14px varying length
                    let dropOpacity = 0.5 + (depthFactor * 0.3) // Closer = brighter

                    // Draw raindrop streak (blue-tinted water)
                    if progress < 0.9 {
                        var dropPath = Path()
                        dropPath.addRoundedRect(
                            in: CGRect(x: x - dropWidth/2, y: y, width: dropWidth, height: dropHeight),
                            cornerSize: CGSize(width: dropWidth/2, height: dropWidth/2)
                        )
                        let rainColor = Color(red: 0.6, green: 0.75, blue: 0.95)
                        context.fill(dropPath, with: .color(rainColor.opacity(dropOpacity)))
                    }

                    // Splash with ripples (blue-tinted water)
                    if progress > 0.85 && progress < 1.0 {
                        let splashProgress = (progress - 0.85) / 0.15
                        let splashY = Double(size.height) - 3

                        let splashColor = Color(red: 0.65, green: 0.8, blue: 1.0)

                        // Main splash
                        let splash1Size = 3.0 + splashProgress * 5.0
                        let splash1Opacity = (1.0 - splashProgress) * dropOpacity * 0.6
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - splash1Size/2, y: splashY - splash1Size/2, width: splash1Size, height: splash1Size)),
                            with: .color(splashColor.opacity(splash1Opacity))
                        )

                        // Outer ripple (only for closer drops)
                        if depthFactor > 0.9 && splashProgress > 0.3 {
                            let rippleSize = 5.0 + (splashProgress - 0.3) * 6.0
                            let rippleOpacity = (1.0 - splashProgress) * 0.3
                            context.stroke(
                                Path(ellipseIn: CGRect(x: x - rippleSize/2, y: splashY - rippleSize/2, width: rippleSize, height: rippleSize)),
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

// MARK: - Snow Animation

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
                    let speed = 3.0 + Double((i * 17) % 15) / 10.0 // 3.0-4.5s
                    let cycleValue = (time + offset) / speed
                    let iteration = Int(floor(cycleValue))
                    let progress = cycleValue - Double(iteration)

                    // Calculate positions (randomized per iteration)
                    let seed = (i &* 12345) &+ (iteration &* 67890)
                    let randomFactor = Double((seed ^ (seed >> 16)) & 0xFFFF) / 65535.0
                    let baseX = randomFactor * Double(width)
                    
                    let drift = sin((time + offset) * 0.5) * 15.0
                    let x = baseX + drift
                    let y = progress * (Double(height) + 20) - 10

                    // Snowflake size
                    let size = 2.0 + Double((i * 23) % 150) / 100.0 // 2-3.5px

                    // Draw snowflake
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

// MARK: - Sun Animation

struct SunView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Position the sun near the center, just to the right of a typical camera notch
                let sunX = (size.width / 2.0) + 140.0
                let sunY = size.height / 2.0
                let center = CGPoint(x: sunX, y: sunY)
                
                // Draw rotating sun rays
                let rayCount = 12
                for i in 0..<rayCount {
                    let angleOffset = (Double.pi * 2.0 / Double(rayCount)) * Double(i)
                    let rotation = time * 0.15 + angleOffset
                    
                    var path = Path()
                    path.move(to: center)
                    
                    let rayLength: CGFloat = 35.0
                    let angle1 = rotation - 0.05
                    let angle2 = rotation + 0.05
                    
                    path.addLine(to: CGPoint(x: center.x + cos(angle1) * rayLength, y: center.y + sin(angle1) * rayLength))
                    path.addLine(to: CGPoint(x: center.x + cos(angle2) * rayLength, y: center.y + sin(angle2) * rayLength))
                    path.closeSubpath()
                    
                    context.fill(path, with: .color(.white.opacity(0.12)))
                }
                
                // Sun Halo pulsing
                let pulse = sin(time * 2.0) * 0.1 + 0.9 // 0.8 to 1.0
                let haloSize = 28.0 * pulse
                context.fill(Path(ellipseIn: CGRect(x: center.x - haloSize/2, y: center.y - haloSize/2, width: haloSize, height: haloSize)), with: .color(.yellow.opacity(0.4)))
                
                // Sun Core
                let coreSize = 14.0
                context.fill(Path(ellipseIn: CGRect(x: center.x - coreSize/2, y: center.y - coreSize/2, width: coreSize, height: coreSize)), with: .color(.white.opacity(0.95)))
                
                // Cinematic Lens Flare Effect
                let flareShiftX = sin(time * 0.4) * 25.0
                let flareShiftY = cos(time * 0.3) * 5.0
                let flareCenter = CGPoint(x: center.x + flareShiftX, y: center.y + flareShiftY)
                
                // 1. Long horizontal anamorphic-style flare
                let hFlareWidth = 150.0 + sin(time) * 10.0
                let hFlareHeight = 1.5
                context.fill(Path(ellipseIn: CGRect(x: flareCenter.x - hFlareWidth/2, y: flareCenter.y - hFlareHeight/2, width: hFlareWidth, height: hFlareHeight)), with: .color(Color(red: 0.8, green: 0.9, blue: 1.0).opacity(0.4)))
                
                let hFlareWidth2 = 80.0
                let hFlareHeight2 = 3.0
                context.fill(Path(ellipseIn: CGRect(x: flareCenter.x - hFlareWidth2/2, y: flareCenter.y - hFlareHeight2/2, width: hFlareWidth2, height: hFlareHeight2)), with: .color(.white.opacity(0.3)))
                
                // 2. Diagonal streaks
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
                
                // 3. Artifact dots (lens ghosting) moving opposite to the flare shift
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
                
                // Floating light dust/lens flares drifting across
                let dustCount = 15
                for i in 0..<dustCount {
                    let offset = Double(i) * 0.5
                    let speed = 0.4 + Double(i % 4) * 0.1
                    let cycle = (time * speed + offset).truncatingRemainder(dividingBy: 15.0)
                    let progress = cycle / 15.0
                    
                    let baseX = (Double(i) * 123.0).truncatingRemainder(dividingBy: Double(size.width))
                    let x = baseX + progress * 80.0 // slowly drifting right
                    
                    let yDrift = sin(time * 0.3 + Double(i)) * 4.0
                    let y = Double(size.height / 2) + yDrift
                    
                    let dustOpacity = sin(progress * .pi) * 0.35 // fades in and out
                    let dustSize = 1.5 + Double(i % 3)
                    
                    let dustColor = i % 2 == 0 ? Color.white : Color.yellow
                    
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dustSize, height: dustSize)), with: .color(dustColor.opacity(dustOpacity)))
                }
            }
        }
    }
}


// MARK: - Clouds Animation

struct CloudView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Clouds inspired by clouds.ts, but smaller, slower, and more transparent
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
                    
                    // Base scale to fit within the small menu bar height (typically ~24px)
                    // We use size.height / 300.0 to scale the clouds to be tiny
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
                        
                        // Combine all parts of the cloud into a single Path
                        // This prevents overlapping areas from accumulating opacity and looking brighter
                        var cloudPath = Path()
                        cloudPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 220, height: 70), cornerSize: CGSize(width: 35, height: 35))
                        cloudPath.addEllipse(in: CGRect(x: 28, y: -42, width: 90, height: 90))
                        cloudPath.addEllipse(in: CGRect(x: 78, y: -58, width: 110, height: 110))
                        
                        // Apply shadow and fill the entire shape at once
                        ctx.addFilter(.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4))
                        ctx.fill(cloudPath, with: .color(.white))
                    }
                }
            }
        }
    }
}


// MARK: - Fog Animation

struct FogView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                let fogLayerCount = 4
                for i in 0..<fogLayerCount {
                    let offset = Double(i) * 30.0
                    let speed = 0.2 + Double(i % 2) * 0.1
                    let cycle = (time * speed + offset).truncatingRemainder(dividingBy: 100.0)
                    let progress = cycle / 100.0
                    
                    // Oscillating drift
                    let xDrift = sin(progress * .pi * 2) * 40.0
                    let xPos = Double(size.width / 2) - 300.0 + xDrift
                    let yPos = Double(size.height / 2) - 10.0 + Double(i) * 5.0
                    
                    let fogWidth = 600.0 // Very wide
                    let fogHeight = 40.0
                    
                    let rect = CGRect(x: xPos, y: yPos, width: fogWidth, height: fogHeight)
                    
                    context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.25)))
                }
            }
            .blur(radius: 8.0) // Soften the fog heavily
        }
    }
}
