import XCTest
import Combine
@testable import WeatherOverlayCore

final class OverlaySettingsTests: XCTestCase {
    var settings: OverlaySettings!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        settings = OverlaySettings()
        cancellables = []
    }

    override func tearDown() {
        settings = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaults() {
        XCTAssertTrue(settings.showAurora)
        XCTAssertFalse(settings.showBottomLine)
        XCTAssertEqual(settings.selectedUnit, .celsius)
        XCTAssertEqual(settings.brightness, 1.0)
        XCTAssertNil(settings.manualWeatherCode)
        XCTAssertNil(settings.manualIsNight)
    }

    func testBrightness_default() {
        XCTAssertEqual(settings.brightness, 1.0)
    }

    // MARK: - Property Changes

    func testToggleShowAurora() {
        settings.showAurora = false
        XCTAssertFalse(settings.showAurora)

        settings.showAurora = true
        XCTAssertTrue(settings.showAurora)
    }

    func testToggleShowBottomLine() {
        settings.showBottomLine = true
        XCTAssertTrue(settings.showBottomLine)
    }

    func testSetBrightness() {
        settings.brightness = 0.5
        XCTAssertEqual(settings.brightness, 0.5)

        settings.brightness = 0.25
        XCTAssertEqual(settings.brightness, 0.25)
    }

    func testSetManualWeatherCode() {
        settings.manualWeatherCode = 61
        XCTAssertEqual(settings.manualWeatherCode, 61)

        settings.manualWeatherCode = nil
        XCTAssertNil(settings.manualWeatherCode)
    }

    func testSetManualIsNight() {
        settings.manualIsNight = true
        XCTAssertTrue(settings.manualIsNight ?? false)

        settings.manualIsNight = nil
        XCTAssertNil(settings.manualIsNight)
    }

    func testPublisherEmitsOnChange() {
        let expectation = expectation(description: "objectWillChange publishes")
        expectation.expectedFulfillmentCount = 3

        settings.objectWillChange
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        settings.showAurora.toggle()
        settings.showBottomLine.toggle()
        settings.selectedUnit = .fahrenheit

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - WeatherUnit

    func testWeatherUnit_allCases() {
        let all = OverlaySettings.WeatherUnit.allCases
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(.celsius))
        XCTAssertTrue(all.contains(.fahrenheit))
    }

    func testWeatherUnit_rawValues() {
        XCTAssertEqual(OverlaySettings.WeatherUnit.celsius.rawValue, "°C")
        XCTAssertEqual(OverlaySettings.WeatherUnit.fahrenheit.rawValue, "°F")
    }

    // MARK: - AuroraStyle

    func testAuroraStyle_allCases() {
        let all = OverlaySettings.AuroraStyle.allCases
        XCTAssertEqual(all.count, 8)
    }

    func testAuroraStyle_weatherCode() {
        XCTAssertNil(OverlaySettings.AuroraStyle.auto.weatherCode)
        XCTAssertEqual(OverlaySettings.AuroraStyle.clearDay.weatherCode, 0)
        XCTAssertEqual(OverlaySettings.AuroraStyle.clearNight.weatherCode, 0)
        XCTAssertEqual(OverlaySettings.AuroraStyle.cloudy.weatherCode, 3)
        XCTAssertEqual(OverlaySettings.AuroraStyle.fog.weatherCode, 45)
        XCTAssertEqual(OverlaySettings.AuroraStyle.rain.weatherCode, 61)
        XCTAssertEqual(OverlaySettings.AuroraStyle.snow.weatherCode, 73)
        XCTAssertEqual(OverlaySettings.AuroraStyle.thunderstorm.weatherCode, 95)
    }

    func testAuroraStyle_forceNight() {
        XCTAssertFalse(OverlaySettings.AuroraStyle.auto.forceNight)
        XCTAssertFalse(OverlaySettings.AuroraStyle.clearDay.forceNight)
        XCTAssertTrue(OverlaySettings.AuroraStyle.clearNight.forceNight)
        XCTAssertFalse(OverlaySettings.AuroraStyle.cloudy.forceNight)
        XCTAssertFalse(OverlaySettings.AuroraStyle.fog.forceNight)
        XCTAssertFalse(OverlaySettings.AuroraStyle.rain.forceNight)
        XCTAssertFalse(OverlaySettings.AuroraStyle.snow.forceNight)
        XCTAssertFalse(OverlaySettings.AuroraStyle.thunderstorm.forceNight)
    }

    func testAuroraStyle_rawValues() {
        XCTAssertEqual(OverlaySettings.AuroraStyle.auto.rawValue, "Auto (Weather-based)")
        XCTAssertEqual(OverlaySettings.AuroraStyle.clearDay.rawValue, "Clear Day")
        XCTAssertEqual(OverlaySettings.AuroraStyle.clearNight.rawValue, "Clear Night")
        XCTAssertEqual(OverlaySettings.AuroraStyle.thunderstorm.rawValue, "Thunderstorm")
    }
}
