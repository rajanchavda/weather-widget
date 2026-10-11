import XCTest
@testable import WeatherOverlayCore

@MainActor
final class NotificationManagerTests: XCTestCase {

    func testAlertEvent_freezingRainTakesPriorityOverRainRange() {
        let event66 = NotificationManager.alertEvent(forWeatherCode: 66, precipitation: 5.0)
        XCTAssertEqual(event66?.title, "Freezing Rain")

        let event67 = NotificationManager.alertEvent(forWeatherCode: 67, precipitation: 0.0)
        XCTAssertEqual(event67?.title, "Freezing Rain")

        let event56 = NotificationManager.alertEvent(forWeatherCode: 56, precipitation: 0.0)
        XCTAssertEqual(event56?.title, "Freezing Rain")
    }

    func testAlertEvent_rainRequiresPrecipitationGate() {
        XCTAssertNil(NotificationManager.alertEvent(forWeatherCode: 61, precipitation: 0.5))
        XCTAssertEqual(
            NotificationManager.alertEvent(forWeatherCode: 61, precipitation: 1.5)?.title,
            "Rain"
        )
        XCTAssertEqual(
            NotificationManager.alertEvent(forWeatherCode: 80, precipitation: 2.0)?.title,
            "Rain"
        )
    }

    func testAlertEvent_thunderstormAndSnowAndFog() {
        XCTAssertEqual(NotificationManager.alertEvent(forWeatherCode: 95, precipitation: 0)?.title, "Thunderstorm")
        XCTAssertEqual(NotificationManager.alertEvent(forWeatherCode: 71, precipitation: 0)?.title, "Snow")
        XCTAssertEqual(NotificationManager.alertEvent(forWeatherCode: 45, precipitation: 0)?.title, "Fog")
        XCTAssertNil(NotificationManager.alertEvent(forWeatherCode: 0, precipitation: 0))
    }

    // MARK: - Onset Detection

    private var weatherManager: WeatherManager!
    private var settings: OverlaySettings!
    private var clock: Date!

    /// 10:20 UTC, so the next forecast hour (11:00) is 40 minutes away.
    private static let baseTime = Date(timeIntervalSince1970: 1_768_040_400)

    private func makeManager() -> NotificationManager {
        weatherManager = WeatherManager(session: .mock)
        settings = OverlaySettings()
        clock = Self.baseTime
        weatherManager.forecastUtcOffsetSeconds = 0
        weatherManager.cityName = "Oslo"
        return NotificationManager(weatherManager: weatherManager, settings: settings, now: { [unowned self] in self.clock })
    }

    /// Loads a forecast whose index 0 is the hour containing `clock`.
    private func setForecast(codes: [Int], temps: [Double]? = nil, precipitation: [Double]? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:00"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        weatherManager.hourlyCodes = codes
        weatherManager.hourlyTemps = temps ?? Array(repeating: 10.0, count: codes.count)
        weatherManager.hourlyPrecipitation = precipitation ?? Array(repeating: 0.0, count: codes.count)
        weatherManager.hourlyTimes = codes.indices.map { formatter.string(from: clock.addingTimeInterval(Double($0) * 3600)) }
        weatherManager.hasData = true
    }

    private func advanceClock(hours: Double) {
        clock = clock.addingTimeInterval(hours * 3600)
    }

    func testOnset_notifiesOnceWithCityAndTime() {
        let manager = makeManager()
        setForecast(codes: [0, 71, 71, 71])

        let alerts = manager.collectAlerts()
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.title, "❄️ Snow")
        XCTAssertEqual(alerts.first?.subtitle, "Oslo")
        XCTAssertEqual(alerts.first?.body, "Snow expected in about 40 minutes")

        XCTAssertTrue(manager.collectAlerts().isEmpty, "Re-evaluating the same forecast must not repeat the alert")
    }

    func testSustainedEvent_doesNotNotifyEveryHour() {
        let manager = makeManager()
        setForecast(codes: [0, 45, 45, 45])
        XCTAssertEqual(manager.collectAlerts().count, 1)

        for _ in 0..<8 {
            advanceClock(hours: 1)
            setForecast(codes: [45, 45, 45, 45])
            XCTAssertTrue(manager.collectAlerts().isEmpty, "Ongoing fog must not alert again as new hours enter the window")
        }
    }

    func testEventAlreadyUnderWay_isNotAnOnset() {
        let manager = makeManager()
        setForecast(codes: [71, 71, 71])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testCurrentHourOnly_doesNotAlert() {
        let manager = makeManager()
        setForecast(codes: [95, 0, 0, 0])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testEventReturningAfterItPassed_notifiesAgain() {
        let manager = makeManager()
        setForecast(codes: [0, 71, 71])
        XCTAssertEqual(manager.collectAlerts().count, 1)

        advanceClock(hours: 5)
        setForecast(codes: [0, 0, 0])
        XCTAssertTrue(manager.collectAlerts().isEmpty)

        advanceClock(hours: 1)
        setForecast(codes: [0, 0, 71])
        XCTAssertEqual(manager.collectAlerts().count, 1, "A new snowfall after a clear spell is a new onset")
    }

    func testFlickeringForecast_isDampedByCooldown() {
        let manager = makeManager()
        setForecast(codes: [0, 71, 71])
        XCTAssertEqual(manager.collectAlerts().count, 1)

        setForecast(codes: [0, 0, 0])
        XCTAssertTrue(manager.collectAlerts().isEmpty)

        setForecast(codes: [0, 71, 71])
        XCTAssertTrue(manager.collectAlerts().isEmpty, "Snow dropping out and back within the cooldown must not re-alert")
    }

    func testLookAhead_ignoresEventsBeyondWindow() {
        let manager = makeManager()
        setForecast(codes: [0, 0, 0, 95])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testMultipleCategories_eachAlertOnce() {
        let manager = makeManager()
        setForecast(codes: [0, 95, 61, 3], precipitation: [0, 0, 2.0, 0])

        XCTAssertEqual(manager.collectAlerts().map(\.title), ["⛈ Thunderstorm", "🌧 Rain"])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testRainBelowPrecipitationGate_doesNotAlert() {
        let manager = makeManager()
        setForecast(codes: [0, 61, 61], precipitation: [0, 0.4, 0.4])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    // MARK: - Freezing Temperature

    func testFreezing_usesSelectedUnit() {
        let manager = makeManager()
        setForecast(codes: [0, 0, 0], temps: [4, -2, -3])

        XCTAssertEqual(manager.collectAlerts().first?.body, "Temperature dropping to -2°C in about 40 minutes — possible ice")

        let fahrenheit = makeManager()
        settings.selectedUnit = .fahrenheit
        setForecast(codes: [0, 0, 0], temps: [4, -2, -3])
        XCTAssertEqual(fahrenheit.collectAlerts().first?.body, "Temperature dropping to 28°F in about 40 minutes — possible ice")
    }

    func testFreezing_coldSpellAlertsOnce() {
        let manager = makeManager()
        setForecast(codes: [0, 0, 0], temps: [2, -1, -4])
        XCTAssertEqual(manager.collectAlerts().count, 1)

        for _ in 0..<12 {
            advanceClock(hours: 1)
            setForecast(codes: [0, 0, 0], temps: [-3, -5, -6])
            XCTAssertTrue(manager.collectAlerts().isEmpty, "A cold spell must not alert once per hour")
        }
    }

    // MARK: - Suppression

    func testStaleData_suppressesAlerts() {
        let manager = makeManager()
        weatherManager.isStale = true
        setForecast(codes: [0, 95, 95], temps: [0, -5, -5])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testAlertsDisabled_producesNothing() {
        let manager = makeManager()
        settings.showWeatherAlerts = false
        setForecast(codes: [0, 95, 95])
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testNoData_producesNothing() {
        let manager = makeManager()
        setForecast(codes: [0, 95, 95])
        weatherManager.hasData = false
        XCTAssertTrue(manager.collectAlerts().isEmpty)
    }

    func testSwitchingCity_alertsForTheNewCity() {
        let manager = makeManager()
        setForecast(codes: [0, 71, 71])
        XCTAssertEqual(manager.collectAlerts().first?.subtitle, "Oslo")

        weatherManager.cityName = "Tromsø"
        setForecast(codes: [0, 71, 71])
        let alerts = manager.collectAlerts()
        XCTAssertEqual(alerts.count, 1, "Another city's snow is a separate event")
        XCTAssertEqual(alerts.first?.subtitle, "Tromsø")
    }
}
