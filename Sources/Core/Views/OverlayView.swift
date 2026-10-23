import SwiftUI

enum OverlayAnimation {
    /// Effects are slow-moving, so 30 fps looks the same as the display's native rate
    /// (up to 120 Hz on ProMotion) at a fraction of the redraws.
    static let frameInterval: TimeInterval = 1.0 / 30.0

    /// Weather changes crossfade the old aurora and effects into the new ones over this long.
    static let weatherCrossfadeDuration: TimeInterval = 1.5

    static var weatherTransition: AnyTransition {
        .opacity.animation(.easeInOut(duration: weatherCrossfadeDuration))
    }

    /// Rain and snow start with a few particles and reach full strength over this long.
    static let particleRampDuration: TimeInterval = 4.0
    static let particleFadeInDuration: TimeInterval = 1.0

    /// Opacity multiplier for particle `index` of `count`, `elapsed` seconds after the effect appeared.
    /// Particles join one after another across the ramp, each fading in so none pops into view mid-fall.
    static func particleRampOpacity(index: Int, count: Int, elapsed: TimeInterval) -> Double {
        guard count > 0 else { return 1 }
        let start = particleRampDuration * Double(index) / Double(count)
        return min(max((elapsed - start) / particleFadeInDuration, 0), 1)
    }
}

struct OverlayView: View {
    @ObservedObject var weatherManager: WeatherManager
    @ObservedObject var settings: OverlaySettings
    @State private var freezeTimestamp: Date = Date()

    private var isEcoActive: Bool {
        settings.ecoMode
    }

    private var freezeDate: Date? {
        isEcoActive ? freezeTimestamp : nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if settings.showAurora {
                    AuroraBackground(
                        colors: currentAuroraColors(),
                        height: geometry.size.height
                    )
                    // A new identity per palette lets the old gradient crossfade into the new one.
                    .id(currentAuroraColors())
                    .transition(OverlayAnimation.weatherTransition)

                    if shouldShowStars() {
                        StarsView(width: geometry.size.width, height: geometry.size.height, freezeDate: freezeDate)
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    let code = getEffectiveWeatherCode()

                    // Partly cloudy keeps the sun (or stars) behind its clouds; overcast hides them.
                    if code >= 0 && code <= 2 && !checkIsNight() {
                        SunView(width: geometry.size.width, height: geometry.size.height, freezeDate: freezeDate)
                            .id("sun")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if let cover = CloudView.CloudCover(weatherCode: code) {
                        CloudView(width: geometry.size.width, height: geometry.size.height, cover: cover, isNight: checkIsNight(), freezeDate: freezeDate)
                            .id("clouds-\(code)-\(checkIsNight())")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if code == 45 || code == 48 {
                        FogView(width: geometry.size.width, height: geometry.size.height / 2, isNight: checkIsNight(), freezeDate: freezeDate)
                            .frame(height: geometry.size.height / 2)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .clipped()
                            .id("fog")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if code >= 51 && code <= 55 && shouldShowRainAnimation() {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .drizzle, freezeDate: freezeDate)
                            .id("rain-drizzle")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if code >= 56 && code <= 67 && shouldShowRainAnimation() {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .light, freezeDate: freezeDate)
                            .id("rain-light")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if code >= 80 && code <= 82 && shouldShowRainAnimation() {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .medium, freezeDate: freezeDate)
                            .id("rain-medium")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if code >= 95 && code <= 99 && shouldShowRainAnimation() {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .heavy, freezeDate: freezeDate)
                            .id("rain-heavy")
                            .transition(OverlayAnimation.weatherTransition)
                    }

                    if let intensity = SnowView.SnowIntensity(weatherCode: code) {
                        SnowView(width: geometry.size.width, height: geometry.size.height, intensity: intensity, freezeDate: freezeDate)
                            .id("snow-\(intensity)")
                            .transition(OverlayAnimation.weatherTransition)
                    }
                }

                if settings.showBottomLine && weatherManager.hourlyTemps.count >= 12 {
                    TemperatureLineView(
                        temps: weatherManager.hourlyTemps,
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
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
        .animation(.easeInOut(duration: 0.5), value: getEffectiveWeatherCode())
        .animation(.easeInOut(duration: 0.5), value: checkIsNight())
        .onChange(of: getEffectiveWeatherCode()) { _ in
            if isEcoActive {
                freezeTimestamp = Date()
            }
        }
        .onChange(of: settings.ecoMode) { newValue in
            freezeTimestamp = Date()
        }
    }

    private func checkIsNight() -> Bool {
        let isNight = settings.isPreviewing ? settings.previewIsNight : settings.manualIsNight
        if let nightValue = isNight {
            return nightValue
        }
        return weatherManager.isNight
    }

    private func getEffectiveWeatherCode() -> Int {
        let code = settings.isPreviewing ? settings.previewWeatherCode : settings.manualWeatherCode
        return code ?? weatherManager.weatherCode
    }

    /// Rain particles require precipitation, but aurora hover preview always shows them.
    private func shouldShowRainAnimation() -> Bool {
        if settings.isPreviewing { return true }
        return (weatherManager.currentPrecipitation ?? 0) > 0
    }

    private func shouldShowStars() -> Bool {
        let code = getEffectiveWeatherCode()
        return checkIsNight() && code >= 0 && code <= 2
    }

    private func currentAuroraColors() -> [Color] {
        let code = getEffectiveWeatherCode()
        let isNight = checkIsNight()
        return getAuroraColors(weatherCode: code, isNight: isNight)
    }
}
