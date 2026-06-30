import Combine

class OverlaySettings: ObservableObject {
    @Published var showAurora: Bool = true
    @Published var showBottomLine: Bool = false
    @Published var selectedUnit: WeatherUnit = .celsius
    @Published var brightness: Double = 1.0
    @Published var manualWeatherCode: Int? = nil
    @Published var manualIsNight: Bool? = nil
    @Published var displayMode: StatusBarDisplayMode = .iconAndTemp
    @Published var ecoMode: Bool = false
    @Published var showWeatherAlerts: Bool = true

    enum StatusBarDisplayMode: String, CaseIterable {
        case iconAndTemp = "Icon + Temperature"
        case iconOnly = "Icon Only"
        case tempOnly = "Temperature Only"
    }

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

    }
}
