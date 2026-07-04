import XCTest
@testable import WeatherOverlayCore

final class RainIntensityTests: XCTestCase {
    func testDrizzleIntensityProperties() {
        let intensity = RainView.RainIntensity.drizzle
        
        XCTAssertEqual(intensity.dropCount, 5)
        XCTAssertEqual(intensity.baseSpeed, 2.0)
        XCTAssertEqual(intensity.baseHeight, 3.0)
        XCTAssertEqual(intensity.windSway, 5.0)
        XCTAssertFalse(intensity.isThunderstorm)
    }

    func testLightIntensityProperties() {
        let intensity = RainView.RainIntensity.light
        
        XCTAssertEqual(intensity.dropCount, 10)
        XCTAssertEqual(intensity.baseSpeed, 0.9)
        XCTAssertEqual(intensity.baseHeight, 6.0)
        XCTAssertEqual(intensity.windSway, 3.0)
        XCTAssertFalse(intensity.isThunderstorm)
    }

    func testMediumIntensityProperties() {
        let intensity = RainView.RainIntensity.medium
        
        XCTAssertEqual(intensity.dropCount, 25)
        XCTAssertEqual(intensity.baseSpeed, 0.7)
        XCTAssertEqual(intensity.baseHeight, 6.0)
        XCTAssertEqual(intensity.windSway, 3.0)
        XCTAssertFalse(intensity.isThunderstorm)
    }

    func testHeavyIntensityProperties() {
        let intensity = RainView.RainIntensity.heavy
        
        XCTAssertEqual(intensity.dropCount, 25)
        XCTAssertEqual(intensity.baseSpeed, 0.65)
        XCTAssertEqual(intensity.baseHeight, 6.0)
        XCTAssertEqual(intensity.windSway, 3.0)
        XCTAssertTrue(intensity.isThunderstorm)
    }
}
