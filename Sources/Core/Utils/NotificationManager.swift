import UserNotifications

/// A notification ready to deliver.
struct WeatherAlert: Equatable {
    let id: String
    let title: String
    let subtitle: String
    let body: String
}

@MainActor
class NotificationManager {
    /// Hours after the current one that are checked for an approaching event.
    static let lookAheadHours = 2
    /// Damps repeats when a forecast flickers in and out of the look-ahead window.
    static let renotifyCooldown: TimeInterval = 3 * 3600

    private static let freezingCategory = "Freezing Temperature"

    private let weatherManager: WeatherManager
    private let settings: OverlaySettings
    private let now: () -> Date
    /// Event categories that are ongoing or already announced; cleared once the event has passed.
    private var activeCategories = Set<String>()
    private var lastNotified: [String: Date] = [:]
    private var trackedCity: String?
    private var authorized = false

    init(weatherManager: WeatherManager, settings: OverlaySettings, now: @escaping () -> Date = Date.init) {
        self.weatherManager = weatherManager
        self.settings = settings
        self.now = now
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                print("[NotificationManager] Authorization \(granted ? "granted" : "denied")")
            }
        }
    }

    func evaluateAndNotify() {
        guard authorized else { return }
        for alert in collectAlerts() {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.subtitle = alert.subtitle
            content.body = alert.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Returns one alert per event that is newly approaching. An event that is already
    /// under way, or was already announced and has not yet passed, produces nothing.
    func collectAlerts() -> [WeatherAlert] {
        guard settings.showWeatherAlerts, weatherManager.hasData else { return [] }
        // A stale forecast no longer lines up with the current hour.
        guard !weatherManager.isStale else { return [] }
        // Hourly window is aligned to the current hour at index 0; alerts look ahead from the next hour.
        guard weatherManager.hourlyCodes.count >= 2 else { return [] }

        let city = weatherManager.cityName
        if trackedCity != city {
            activeCategories.removeAll()
            lastNotified.removeAll()
            trackedCity = city
        }

        let current = Set(events(atHour: 0).map(\.category))
        var upcoming: [(category: String, title: String, time: String, body: (String) -> String)] = []
        let lastHour = min(Self.lookAheadHours, weatherManager.hourlyCodes.count - 1)
        for hour in 1...lastHour {
            for event in events(atHour: hour) where !upcoming.contains(where: { $0.category == event.category }) {
                upcoming.append((event.category, event.title, weatherManager.hourlyTimes[safe: hour] ?? "", event.body))
            }
        }

        let upcomingCategories = Set(upcoming.map(\.category))
        activeCategories = activeCategories.filter { current.contains($0) || upcomingCategories.contains($0) }
        activeCategories.formUnion(current)

        var alerts: [WeatherAlert] = []
        for event in upcoming where !activeCategories.contains(event.category) {
            activeCategories.insert(event.category)
            if let last = lastNotified[event.category], now().timeIntervalSince(last) < Self.renotifyCooldown {
                continue
            }
            lastNotified[event.category] = now()

            let when: String
            if let minutes = minutesAway(event.time), minutes >= 1 {
                when = "in about \(minutes) minutes"
            } else {
                when = "at \(formatTime(event.time))"
            }
            alerts.append(WeatherAlert(
                id: "\(event.category)|\(city)|\(event.time)",
                title: event.title,
                subtitle: city,
                body: event.body(when)
            ))
        }
        return alerts
    }

    /// Alert-worthy conditions in one forecast hour. `body` takes the "in about N minutes" phrase.
    private func events(atHour hour: Int) -> [(category: String, title: String, body: (String) -> String)] {
        var result: [(category: String, title: String, body: (String) -> String)] = []

        let code = weatherManager.hourlyCodes[safe: hour] ?? 0
        let precip = weatherManager.hourlyPrecipitation[safe: hour] ?? 0
        if let event = Self.alertEvent(forWeatherCode: code, precipitation: precip) {
            let suffix = event.bodySuffix.map { " \($0)" } ?? ""
            result.append((event.title, "\(event.emoji) \(event.title)", { "\(event.title) expected \($0)\(suffix)" }))
        }

        if let temp = weatherManager.hourlyTemps[safe: hour], temp <= 0 {
            let displayed = formatTemperature(temp)
            result.append((
                Self.freezingCategory,
                "⚠️ \(Self.freezingCategory)",
                { "Temperature dropping to \(displayed) \($0) — possible ice" }
            ))
        }
        return result
    }

    private func formatTemperature(_ celsius: Double) -> String {
        let value = settings.selectedUnit == .fahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
        return "\(Int(value.rounded()))\(settings.selectedUnit.rawValue)"
    }

    /// Maps a WMO code (+ precip) to a weather alert. Freezing rain is classified before rain.
    nonisolated static func alertEvent(
        forWeatherCode code: Int,
        precipitation precip: Double
    ) -> (emoji: String, title: String, bodySuffix: String?)? {
        if (95...99).contains(code) {
            return ("⛈", "Thunderstorm", nil)
        }
        if (56...57).contains(code) || (66...67).contains(code) {
            return ("⚠️", "Freezing Rain", "— possible ice")
        }
        if (61...65).contains(code) || (80...82).contains(code) {
            guard precip > 1.0 else { return nil }
            return ("🌧", "Rain", nil)
        }
        if (71...77).contains(code) || (85...86).contains(code) {
            return ("❄️", "Snow", nil)
        }
        if (45...48).contains(code) {
            return ("🌫", "Fog", nil)
        }
        return nil
    }

    private func formatTime(_ iso: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = forecastTimeZone()
        guard let date = df.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        out.timeZone = forecastTimeZone()
        return out.string(from: date)
    }

    private func minutesAway(_ iso: String) -> Int? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = forecastTimeZone()
        guard let date = df.date(from: iso) else { return nil }
        let diff = date.timeIntervalSince(now())
        guard diff > 0 else { return nil }
        return Int(ceil(diff / 60))
    }

    private func forecastTimeZone() -> TimeZone {
        if let offset = weatherManager.forecastUtcOffsetSeconds,
           let tz = TimeZone(secondsFromGMT: offset) {
            return tz
        }
        return TimeZone.current
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
