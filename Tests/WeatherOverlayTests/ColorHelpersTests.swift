import XCTest
import SwiftUI
import AppKit
@testable import WeatherOverlayCore

final class ColorHelpersTests: XCTestCase {

    // MARK: - getTemperatureColor

    func testGetTemperatureColor_freezing() {
        assertColor(getTemperatureColor(-5), red: 0.0, green: 0.8, blue: 1.0)
    }

    func testGetTemperatureColor_freezingAtBoundary() {
        assertColor(getTemperatureColor(-0.1), red: 0.0, green: 0.8, blue: 1.0)
    }

    func testGetTemperatureColor_coldAtFreezingBoundary() {
        assertColor(getTemperatureColor(0), red: 0.2, green: 0.6, blue: 0.9)
    }

    func testGetTemperatureColor_cold() {
        assertColor(getTemperatureColor(7), red: 0.2, green: 0.6, blue: 0.9)
    }

    func testGetTemperatureColor_coldAtUpperBoundary() {
        assertColor(getTemperatureColor(14.9), red: 0.2, green: 0.6, blue: 0.9)
    }

    func testGetTemperatureColor_mild() {
        assertColor(getTemperatureColor(18), red: 0.3, green: 0.8, blue: 0.5)
    }

    func testGetTemperatureColor_mildAtBoundary() {
        assertColor(getTemperatureColor(15), red: 0.3, green: 0.8, blue: 0.5)
    }

    func testGetTemperatureColor_mildAtUpperBoundary() {
        assertColor(getTemperatureColor(21.9), red: 0.3, green: 0.8, blue: 0.5)
    }

    func testGetTemperatureColor_warm() {
        assertColor(getTemperatureColor(25), red: 0.95, green: 0.7, blue: 0.1)
    }

    func testGetTemperatureColor_warmAtBoundary() {
        assertColor(getTemperatureColor(22), red: 0.95, green: 0.7, blue: 0.1)
    }

    func testGetTemperatureColor_warmAtUpperBoundary() {
        assertColor(getTemperatureColor(29.9), red: 0.95, green: 0.7, blue: 0.1)
    }

    func testGetTemperatureColor_hot() {
        assertColor(getTemperatureColor(35), red: 0.9, green: 0.2, blue: 0.1)
    }

    func testGetTemperatureColor_hotAtBoundary() {
        assertColor(getTemperatureColor(30), red: 0.9, green: 0.2, blue: 0.1)
    }

    func testGetTemperatureColor_extremeCold() {
        assertColor(getTemperatureColor(-20), red: 0.0, green: 0.8, blue: 1.0)
    }

    func testGetTemperatureColor_extremeHot() {
        assertColor(getTemperatureColor(50), red: 0.9, green: 0.2, blue: 0.1)
    }

    // MARK: - getAuroraColors

    func testGetAuroraColors_clearDay() {
        let colors = getAuroraColors(weatherCode: 0, isNight: false)
        XCTAssertEqual(colors.count, 3)
    }

    func testGetAuroraColors_clearNight() {
        let colors = getAuroraColors(weatherCode: 0, isNight: true)
        XCTAssertEqual(colors.count, 3)
    }

    func testGetAuroraColors_clearCode1() {
        XCTAssertEqual(getAuroraColors(weatherCode: 1, isNight: false).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 1, isNight: true).count, 3)
    }

    func testGetAuroraColors_cloudy() {
        XCTAssertEqual(getAuroraColors(weatherCode: 2, isNight: false).count, 4)
        XCTAssertEqual(getAuroraColors(weatherCode: 3, isNight: true).count, 4)
    }

    func testGetAuroraColors_fog() {
        XCTAssertFalse(getAuroraColors(weatherCode: 45, isNight: false).isEmpty)
        XCTAssertFalse(getAuroraColors(weatherCode: 48, isNight: true).isEmpty)
    }

    func testGetAuroraColors_rain() {
        XCTAssertEqual(getAuroraColors(weatherCode: 51, isNight: false).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 67, isNight: true).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 80, isNight: false).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 82, isNight: true).count, 3)
    }

    func testGetAuroraColors_snow() {
        XCTAssertEqual(getAuroraColors(weatherCode: 71, isNight: false).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 77, isNight: true).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 85, isNight: false).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 86, isNight: true).count, 3)
    }

    func testGetAuroraColors_thunderstorm() {
        XCTAssertEqual(getAuroraColors(weatherCode: 95, isNight: false).count, 3)
        XCTAssertEqual(getAuroraColors(weatherCode: 99, isNight: true).count, 3)
    }

    func testGetAuroraColors_default() {
        let colors = getAuroraColors(weatherCode: 100, isNight: false)
        XCTAssertEqual(colors.count, 2)
    }

    // MARK: - Helpers

    private func assertColor(_ color: Color, red: Double, green: Double, blue: Double, file: StaticString = #file, line: UInt = #line) {
        let nsColor = NSColor(color)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            XCTFail("Could not convert color to sRGB", file: file, line: line)
            return
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Double(r), red, accuracy: 0.01, "red mismatch", file: file, line: line)
        XCTAssertEqual(Double(g), green, accuracy: 0.01, "green mismatch", file: file, line: line)
        XCTAssertEqual(Double(b), blue, accuracy: 0.01, "blue mismatch", file: file, line: line)
    }
}
