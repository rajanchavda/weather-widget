import XCTest
import Cocoa
@testable import WeatherOverlayCore

@MainActor
final class AppDelegateTests: XCTestCase {
    var appDelegate: AppDelegate!
    
    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }
    
    override func tearDown() {
        appDelegate = nil
        super.tearDown()
    }
    
    func testMenuDelegate_highlightAuroraStyle() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Thunderstorm", action: nil, keyEquivalent: "")
        item.representedObject = OverlaySettings.AuroraStyle.thunderstorm
        
        // Before highlight
        XCTAssertFalse(appDelegate.settings.isPreviewing)
        XCTAssertNil(appDelegate.settings.previewWeatherCode)
        XCTAssertNil(appDelegate.settings.previewIsNight)
        
        // Trigger highlight
        appDelegate.menu(menu, willHighlight: item)
        
        // After highlight
        XCTAssertTrue(appDelegate.settings.isPreviewing)
        XCTAssertEqual(appDelegate.settings.previewWeatherCode, 95)
    }
    
    func testMenuDelegate_highlightClearDay() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Clear Day", action: nil, keyEquivalent: "")
        item.representedObject = OverlaySettings.AuroraStyle.clearDay
        
        appDelegate.menu(menu, willHighlight: item)
        
        XCTAssertTrue(appDelegate.settings.isPreviewing)
        XCTAssertEqual(appDelegate.settings.previewWeatherCode, 0)
        XCTAssertEqual(appDelegate.settings.previewIsNight, false)
    }
    
    func testMenuDelegate_highlightClearNight() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Clear Night", action: nil, keyEquivalent: "")
        item.representedObject = OverlaySettings.AuroraStyle.clearNight
        
        appDelegate.menu(menu, willHighlight: item)
        
        XCTAssertTrue(appDelegate.settings.isPreviewing)
        XCTAssertEqual(appDelegate.settings.previewWeatherCode, 0)
        XCTAssertEqual(appDelegate.settings.previewIsNight, true)
    }
    
    func testMenuDelegate_highlightAuto() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Auto", action: nil, keyEquivalent: "")
        item.representedObject = OverlaySettings.AuroraStyle.auto
        
        appDelegate.menu(menu, willHighlight: item)
        
        XCTAssertTrue(appDelegate.settings.isPreviewing)
        XCTAssertNil(appDelegate.settings.previewWeatherCode)
        XCTAssertNil(appDelegate.settings.previewIsNight)
    }
    
    func testMenuDelegate_highlightNonAuroraStyle() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Other", action: nil, keyEquivalent: "")
        
        appDelegate.settings.isPreviewing = true
        appDelegate.menu(menu, willHighlight: item)
        
        // Should reset
        XCTAssertFalse(appDelegate.settings.isPreviewing)
    }
    
    func testMenuDelegate_highlightNilItem() {
        let menu = NSMenu()
        
        appDelegate.settings.isPreviewing = true
        appDelegate.menu(menu, willHighlight: nil)
        
        // Should reset
        XCTAssertFalse(appDelegate.settings.isPreviewing)
    }
    
    func testMenuDelegate_menuDidClose() {
        let menu = NSMenu()
        appDelegate.settings.isPreviewing = true
        
        appDelegate.menuDidClose(menu)
        
        XCTAssertFalse(appDelegate.settings.isPreviewing)
    }
}
