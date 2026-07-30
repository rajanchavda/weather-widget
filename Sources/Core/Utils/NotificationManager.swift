import UserNotifications

@MainActor
class NotificationManager {
    private let weatherManager: WeatherManager
    private let settings: OverlaySettings
    private var alertedEvents = Set<String>()
    private var authorized = false

    init(weatherManager: WeatherManager, settings: OverlaySettings) {
        self.weatherManager = weatherManager
        self.settings = settings
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
        guard authorized, settings.showWeatherAlerts else { return }
        guard weatherManager.hasData else { return }
        // Hourly window is aligned to the current hour at index 0; alerts look ahead from the next hour.
        guard weatherManager.hourlyCodes.count >= 2 else { return }

        let startIndex = 1
        let endIndex = min(startIndex + 2, weatherManager.hourlyCodes.count)

        for i in startIndex..<endIndex {
            let code = weatherManager.hourlyCodes[safe: i] ?? 0
            let timeStr = weatherManager.hourlyTimes[safe: i] ?? ""
            let precip = weatherManager.hourlyPrecipitation[safe: i] ?? 0

            guard let event = Self.alertEvent(forWeatherCode: code, precipitation: precip) else { continue }
            notifyIfNeeded(emoji: event.emoji, title: event.title, time: timeStr, bodySuffix: event.bodySuffix)
        }

        for i in startIndex..<endIndex {
            guard let temp = weatherManager.hourlyTemps[safe: i], temp <= 0 else { continue }
            let timeStr = weatherManager.hourlyTimes[safe: i] ?? ""
            let key = "freezing:\(timeStr)"
            guard !alertedEvents.contains(key) else { continue }
            alertedEvents.insert(key)

            let displayTime = formatTime(timeStr)
            let minAway = minutesAway(timeStr)
            let body: String
            if let min = minAway, min >= 1 {
                body = "Temperature dropping to \(Int(temp))°C in about \(min) minutes — possible ice"
            } else {
                body = "Temperature dropping to \(Int(temp))°C at \(displayTime) — possible ice"
            }

            let content = UNMutableNotificationContent()
            content.title = "⚠️ Freezing Temperature"
            content.body = body
            content.sound = .default

            schedule(content, id: key)
        }
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

    private func notifyIfNeeded(emoji: String, title: String, time: String, bodySuffix: String? = nil) {
        let key = "\(title):\(time)"
        guard !alertedEvents.contains(key) else { return }
        alertedEvents.insert(key)

        let displayTime = formatTime(time)
        let minAway = minutesAway(time)
        let body: String
        if let min = minAway, min >= 1 {
            body = "\(title) expected in about \(min) minutes" + (bodySuffix.map { " \($0)" } ?? "")
        } else {
            body = "\(title) expected at \(displayTime)" + (bodySuffix.map { " \($0)" } ?? "")
        }

        let content = UNMutableNotificationContent()
        content.title = "\(emoji) \(title)"
        content.body = body
        content.sound = .default

        schedule(content, id: key)
    }

    private func schedule(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        let diff = date.timeIntervalSinceNow
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
