import SwiftUI

struct OverlayView: View {
    @ObservedObject var weatherManager: WeatherManager
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if settings.showAurora {
                    AuroraBackground(
                        colors: currentAuroraColors(),
                        height: geometry.size.height
                    )
                    .transition(.opacity)

                    if shouldShowStars() {
                        StarsView(width: geometry.size.width, height: geometry.size.height)
                    }

                    let code = getEffectiveWeatherCode()

                    if (code == 0 || code == 1) && !checkIsNight() {
                        SunView(width: geometry.size.width, height: geometry.size.height)
                            .id("sun-\(code)")
                    }

                    if code == 2 || code == 3 {
                        CloudView(width: geometry.size.width, height: geometry.size.height)
                            .id("clouds-\(code)")
                    }

                    if code == 45 || code == 48 {
                        FogView(width: geometry.size.width, height: geometry.size.height / 2, isNight: checkIsNight())
                            .frame(height: geometry.size.height / 2)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .clipped()
                            .id("fog-\(code)")
                    }

                    if code >= 51 && code <= 67 {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .light)
                            .id("rain-light-\(code)")
                    }

                    if code >= 80 && code <= 82 {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .medium)
                            .id("rain-medium-\(code)")
                    }

                    if code >= 95 && code <= 99 {
                        RainView(width: geometry.size.width, height: geometry.size.height, intensity: .heavy)
                            .id("rain-heavy-\(code)")
                    }

                    if (code >= 71 && code <= 77) || (code >= 85 && code <= 86) {
                        SnowView(width: geometry.size.width, height: geometry.size.height)
                            .id("snow-\(code)")
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

    private func currentAuroraColors() -> [Color] {
        let code = settings.manualWeatherCode ?? weatherManager.weatherCode
        let isNight = checkIsNight()
        return getAuroraColors(weatherCode: code, isNight: isNight)
    }
}
