import XCTest
@testable import WeatherOverlayCore

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

    /// Index 0 is the current hour after slicing; alerts must look ahead from index 1.
    func testAlertLookahead_skipsCurrentHourIndex() {
        let hourlyCodes = [0, 95, 61, 3] // current clear, next thunderstorm, then rain
        let startIndex = 1
        let endIndex = min(startIndex + 2, hourlyCodes.count)
        let alertedTitles = (startIndex..<endIndex).compactMap { index in
            NotificationManager.alertEvent(
                forWeatherCode: hourlyCodes[index],
                precipitation: index == 2 ? 2.0 : 0
            )?.title
        }
        XCTAssertEqual(alertedTitles, ["Thunderstorm", "Rain"])
        XCTAssertNil(
            NotificationManager.alertEvent(forWeatherCode: hourlyCodes[0], precipitation: 0),
            "Current-hour clear conditions must not produce an alert"
        )
    }
}
