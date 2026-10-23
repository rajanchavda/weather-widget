import XCTest
@testable import WeatherOverlayCore

final class SnowIntensityTests: XCTestCase {
    func testWeatherCodeMapping() {
        XCTAssertEqual(SnowView.SnowIntensity(weatherCode: 71), .light)
        XCTAssertEqual(SnowView.SnowIntensity(weatherCode: 77), .light)
        XCTAssertEqual(SnowView.SnowIntensity(weatherCode: 85), .light)
        XCTAssertEqual(SnowView.SnowIntensity(weatherCode: 73), .moderate)
        XCTAssertEqual(SnowView.SnowIntensity(weatherCode: 75), .heavy)
        XCTAssertEqual(SnowView.SnowIntensity(weatherCode: 86), .heavy)
        XCTAssertNil(SnowView.SnowIntensity(weatherCode: 61))
        XCTAssertNil(SnowView.SnowIntensity(weatherCode: 3))
    }

    func testLightIntensityProperties() {
        let intensity = SnowView.SnowIntensity.light

        XCTAssertEqual(intensity.flakeCount, 18)
        XCTAssertEqual(intensity.baseSpeed, 5.0)
        XCTAssertEqual(intensity.windDrift, 6.0)
        XCTAssertEqual(intensity.frostHeight, 2.0)
    }

    func testModerateIntensityProperties() {
        let intensity = SnowView.SnowIntensity.moderate

        XCTAssertEqual(intensity.flakeCount, 35)
        XCTAssertEqual(intensity.baseSpeed, 4.0)
        XCTAssertEqual(intensity.windDrift, 8.0)
        XCTAssertEqual(intensity.frostHeight, 3.0)
    }

    func testHeavyIntensityProperties() {
        let intensity = SnowView.SnowIntensity.heavy

        XCTAssertEqual(intensity.flakeCount, 60)
        XCTAssertEqual(intensity.baseSpeed, 3.2)
        XCTAssertEqual(intensity.windDrift, 14.0)
        XCTAssertEqual(intensity.frostHeight, 4.0)
    }
}
