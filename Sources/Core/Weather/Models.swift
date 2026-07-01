import Foundation

// MARK: - Manual Location Override

struct ManualLocation: Codable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double

    private static let defaultsKey = "WeatherOverlay.manualLocation"

    static func load() -> ManualLocation? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ManualLocation.self, from: data)
    }

    static func save(_ value: ManualLocation?) {
        let defaults = UserDefaults.standard
        if let value = value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}

// MARK: - JSON Structures for Decoding

struct GeoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let city: String?
}

struct FreeGeoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let cityName: String?
}

struct GeocodingResponse: Codable {
    let results: [Result]?
    struct Result: Codable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }
}

struct WeatherResponse: Codable {
    let current: CurrentWeather
    let hourly: HourlyWeather

    struct CurrentWeather: Codable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }

    struct HourlyWeather: Codable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let precipitation: [Double]?
    }
}

// MARK: - Air Quality

struct AirQualityResponse: Codable {
    let current: CurrentAirQuality

    struct CurrentAirQuality: Codable {
        let europeanAqi: Double?

        enum CodingKeys: String, CodingKey {
            case europeanAqi = "european_aqi"
        }
    }
}

enum AQICategory: String, CaseIterable {
    case good
    case fair
    case moderate
    case poor
    case veryPoor
    case extremelyPoor

    var label: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .moderate: return "Moderate"
        case .poor: return "Poor"
        case .veryPoor: return "Very Poor"
        case .extremelyPoor: return "Extremely Poor"
        }
    }

    static func from(europeanAqi: Double) -> AQICategory {
        switch europeanAqi {
        case ..<20:  return .good
        case ..<40:  return .fair
        case ..<60:  return .moderate
        case ..<80:  return .poor
        case ..<100: return .veryPoor
        default:     return .extremelyPoor
        }
    }
}
