import Combine
import Foundation

class OverlaySettings: ObservableObject {
    @Published var showAurora: Bool = true { didSet { save(showAurora, .showAurora) } }
    @Published var showBottomLine: Bool = false { didSet { save(showBottomLine, .showBottomLine) } }
    @Published var selectedUnit: WeatherUnit = .celsius { didSet { save(selectedUnit.rawValue, .selectedUnit) } }
    @Published var brightness: Double = 1.0 {
        didSet {
            // Eco Mode dims temporarily; only the user's own level is stored.
            if !ecoMode { save(brightness, .brightness) }
        }
    }
    @Published var manualWeatherCode: Int? = nil { didSet { save(manualWeatherCode, .manualWeatherCode) } }
    @Published var manualIsNight: Bool? = nil { didSet { save(manualIsNight, .manualIsNight) } }
    @Published var displayMode: StatusBarDisplayMode = .iconAndTemp { didSet { save(displayMode.rawValue, .displayMode) } }
    /// Not stored on change: battery-triggered Eco Mode must not outlive the session.
    /// A manual choice is stored through `saveManualEcoMode()`.
    @Published var ecoMode: Bool = false {
        didSet {
            if !ecoMode { save(brightness, .brightness) }
        }
    }
    @Published var showWeatherAlerts: Bool = true { didSet { save(showWeatherAlerts, .showWeatherAlerts) } }
    @Published var showAQI: Bool = false { didSet { save(showAQI, .showAQI) } }

    // Hover Preview State
    @Published var isPreviewing: Bool = false
    @Published var previewWeatherCode: Int? = nil
    @Published var previewIsNight: Bool? = nil

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

    // MARK: - Persistence

    enum Key: String, CaseIterable {
        case showAurora, showBottomLine, selectedUnit, brightness, manualWeatherCode
        case manualIsNight, displayMode, ecoMode, showWeatherAlerts, showAQI

        var defaultsKey: String { "WeatherOverlay.settings.\(rawValue)" }
    }

    private let defaults: UserDefaults?

    /// Pass `nil` for in-memory settings that are never written to disk.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let defaults else { return }

        if let value = defaults.object(forKey: Key.showAurora.defaultsKey) as? Bool { showAurora = value }
        if let value = defaults.object(forKey: Key.showBottomLine.defaultsKey) as? Bool { showBottomLine = value }
        if let raw = defaults.string(forKey: Key.selectedUnit.defaultsKey), let value = WeatherUnit(rawValue: raw) {
            selectedUnit = value
        }
        if let value = defaults.object(forKey: Key.brightness.defaultsKey) as? Double {
            brightness = min(max(value, 0.25), 1.0)
        }
        manualWeatherCode = defaults.object(forKey: Key.manualWeatherCode.defaultsKey) as? Int
        manualIsNight = defaults.object(forKey: Key.manualIsNight.defaultsKey) as? Bool
        if let raw = defaults.string(forKey: Key.displayMode.defaultsKey), let value = StatusBarDisplayMode(rawValue: raw) {
            displayMode = value
        }
        if let value = defaults.object(forKey: Key.ecoMode.defaultsKey) as? Bool { ecoMode = value }
        if let value = defaults.object(forKey: Key.showWeatherAlerts.defaultsKey) as? Bool { showWeatherAlerts = value }
        if let value = defaults.object(forKey: Key.showAQI.defaultsKey) as? Bool { showAQI = value }
    }

    /// Stores the current Eco Mode state as the user's own choice.
    func saveManualEcoMode() {
        save(ecoMode, .ecoMode)
    }

    static func removePersistedValues(from defaults: UserDefaults) {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.defaultsKey)
        }
    }

    private func save(_ value: Any?, _ key: Key) {
        guard let defaults else { return }
        if let value {
            defaults.set(value, forKey: key.defaultsKey)
        } else {
            defaults.removeObject(forKey: key.defaultsKey)
        }
    }
}
