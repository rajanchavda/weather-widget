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
        guard weatherManager.hourlyCodes.count >= 1 else { return }

        let lookaheadCount = min(2, weatherManager.hourlyCodes.count)

        for i in 0..<lookaheadCount {
            let code = weatherManager.hourlyCodes[safe: i] ?? 0
            let timeStr = weatherManager.hourlyTimes[safe: i] ?? ""
            let precip = weatherManager.hourlyPrecipitation[safe: i] ?? 0

            if (95...99).contains(code) {
                notifyIfNeeded(emoji: "⛈", title: "Thunderstorm", time: timeStr)
            } else if (61...67).contains(code) || (80...82).contains(code) {
                if precip > 1.0 {
                    notifyIfNeeded(emoji: "🌧", title: "Rain", time: timeStr)
                }
            } else if (56...57).contains(code) || (66...67).contains(code) {
                notifyIfNeeded(emoji: "⚠️", title: "Freezing Rain", time: timeStr, bodySuffix: "— possible ice")
            } else if (71...77).contains(code) || (85...86).contains(code) {
                notifyIfNeeded(emoji: "❄️", title: "Snow", time: timeStr)
            } else if (45...48).contains(code) {
                notifyIfNeeded(emoji: "🌫", title: "Fog", time: timeStr)
            }
        }

        for i in 0..<lookaheadCount {
            let temp = weatherManager.hourlyTemps[safe: i] ?? 0
            guard temp <= 0 else { continue }
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
        guard let date = df.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        return out.string(from: date)
    }

    private func minutesAway(_ iso: String) -> Int? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let date = df.date(from: iso) else { return nil }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return nil }
        return Int(ceil(diff / 60))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
