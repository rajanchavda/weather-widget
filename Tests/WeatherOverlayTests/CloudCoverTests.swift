import XCTest
import SwiftUI
@testable import WeatherOverlayCore

final class CloudCoverTests: XCTestCase {
    func testWeatherCodeMapping() {
        XCTAssertNil(CloudView.CloudCover(weatherCode: 0))
        XCTAssertEqual(CloudView.CloudCover(weatherCode: 1), .few)
        XCTAssertEqual(CloudView.CloudCover(weatherCode: 2), .partly)
        XCTAssertEqual(CloudView.CloudCover(weatherCode: 3), .overcast)
        XCTAssertNil(CloudView.CloudCover(weatherCode: 45))
    }

    func testCloudCountGrowsWithCover() {
        XCTAssertEqual(CloudView.CloudCover.few.cloudCount, 2)
        XCTAssertEqual(CloudView.CloudCover.partly.cloudCount, 3)
        XCTAssertEqual(CloudView.CloudCover.overcast.cloudCount, 6)
    }

    func testOvercastIsDarkerThanPartlyCloudy() {
        XCTAssertNotEqual(
            CloudView.CloudCover.overcast.gradientColors(isNight: false),
            CloudView.CloudCover.partly.gradientColors(isNight: false)
        )
        XCTAssertEqual(CloudView.CloudCover.partly.gradientColors(isNight: false).first, .white)
    }

    func testNightCloudsAreNotWhite() {
        for cover in [CloudView.CloudCover.few, .partly, .overcast] {
            let night = cover.gradientColors(isNight: true)
            XCTAssertNotEqual(night, cover.gradientColors(isNight: false))
            XCTAssertFalse(night.contains(.white))
        }
    }
}
