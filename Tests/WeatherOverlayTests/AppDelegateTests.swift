import XCTest
import Cocoa
@testable import WeatherOverlayCore

@MainActor
final class AppDelegateTests: XCTestCase {
    var appDelegate: AppDelegate!
    
    override func setUp() {
        super.setUp()
        OverlaySettings.removePersistedValues(from: .standard)
        appDelegate = AppDelegate()
    }
    
    override func tearDown() {
        appDelegate = nil
        OverlaySettings.removePersistedValues(from: .standard)
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

    func testMenuDelegate_highlightRainClearsStickyNight() {
        let menu = NSMenu()
        let nightItem = NSMenuItem(title: "Clear Night", action: nil, keyEquivalent: "")
        nightItem.representedObject = OverlaySettings.AuroraStyle.clearNight
        appDelegate.menu(menu, willHighlight: nightItem)
        XCTAssertEqual(appDelegate.settings.previewIsNight, true)

        let rainItem = NSMenuItem(title: "Rainy", action: nil, keyEquivalent: "")
        rainItem.representedObject = OverlaySettings.AuroraStyle.rain
        appDelegate.menu(menu, willHighlight: rainItem)

        XCTAssertTrue(appDelegate.settings.isPreviewing)
        XCTAssertEqual(appDelegate.settings.previewWeatherCode, 61)
        XCTAssertNil(appDelegate.settings.previewIsNight)
    }
    
    func testMenuDelegate_highlightNonAuroraStyle() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Other", action: nil, keyEquivalent: "")
        
        appDelegate.settings.isPreviewing = true
        appDelegate.settings.previewWeatherCode = 95
        appDelegate.settings.previewIsNight = true
        appDelegate.menu(menu, willHighlight: item)
        
        XCTAssertFalse(appDelegate.settings.isPreviewing)
        XCTAssertNil(appDelegate.settings.previewWeatherCode)
        XCTAssertNil(appDelegate.settings.previewIsNight)
    }
    
    func testMenuDelegate_highlightNilItem() {
        let menu = NSMenu()
        
        appDelegate.settings.isPreviewing = true
        appDelegate.settings.previewWeatherCode = 0
        appDelegate.menu(menu, willHighlight: nil)
        
        XCTAssertFalse(appDelegate.settings.isPreviewing)
        XCTAssertNil(appDelegate.settings.previewWeatherCode)
        XCTAssertNil(appDelegate.settings.previewIsNight)
    }
    
    func testMenuDelegate_menuDidClose() {
        let menu = NSMenu()
        appDelegate.settings.isPreviewing = true
        appDelegate.settings.previewWeatherCode = 95
        appDelegate.settings.previewIsNight = true
        
        appDelegate.menuDidClose(menu)
        
        XCTAssertFalse(appDelegate.settings.isPreviewing)
        XCTAssertNil(appDelegate.settings.previewWeatherCode)
        XCTAssertNil(appDelegate.settings.previewIsNight)
    }

    func testToggleEcoMode_marksAsUserInitiated() {
        appDelegate.autoEnabledEco = true
        appDelegate.settings.ecoMode = false

        appDelegate.toggleEcoMode()

        XCTAssertTrue(appDelegate.settings.ecoMode)
        XCTAssertFalse(appDelegate.autoEnabledEco, "Manual Eco enable must not be auto-cleared on AC")
        XCTAssertFalse(appDelegate.userDisabledEco)
    }

    func testToggleEcoMode_offSetsUserDisabledFlag() {
        appDelegate.settings.ecoMode = true
        appDelegate.autoEnabledEco = true

        appDelegate.toggleEcoMode()

        XCTAssertFalse(appDelegate.settings.ecoMode)
        XCTAssertTrue(appDelegate.userDisabledEco)
        XCTAssertFalse(appDelegate.autoEnabledEco)
    }

    func testToggleEcoMode_offRestoresPreviousBrightness() {
        appDelegate.settings.brightness = 0.75

        appDelegate.toggleEcoMode()
        XCTAssertEqual(appDelegate.settings.brightness, 0.50)

        appDelegate.toggleEcoMode()
        XCTAssertEqual(appDelegate.settings.brightness, 0.75, "Leaving Eco Mode must restore the pre-Eco brightness")
    }

    func testToggleEcoMode_onDoesNotRaiseLowerBrightness() {
        appDelegate.settings.brightness = 0.25

        appDelegate.toggleEcoMode()
        XCTAssertEqual(appDelegate.settings.brightness, 0.25, "Eco Mode must not brighten a dimmer setting")

        appDelegate.toggleEcoMode()
        XCTAssertEqual(appDelegate.settings.brightness, 0.25)
    }

    func testToggleEcoMode_offKeepsBrightnessChosenDuringEco() {
        appDelegate.settings.brightness = 1.0
        appDelegate.toggleEcoMode()

        let item = NSMenuItem(title: "75%", action: nil, keyEquivalent: "")
        item.representedObject = 0.75
        appDelegate.setBrightness(item)

        appDelegate.toggleEcoMode()
        XCTAssertEqual(appDelegate.settings.brightness, 0.75, "A level picked during Eco Mode must not be overwritten")
    }

    func testToggleEcoMode_updatesNestedMenuCheckmark() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        appDelegate.statusItem = statusItem
        appDelegate.menuBarManager.buildMenu(for: statusItem)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        guard let menu = statusItem.menu,
              let ecoItem = findMenuItem(title: "Eco Mode", in: menu) else {
            return XCTFail("Eco Mode menu item should exist under Settings")
        }

        XCTAssertEqual(ecoItem.state, .off)

        appDelegate.toggleEcoMode()
        XCTAssertTrue(appDelegate.settings.ecoMode)
        XCTAssertEqual(ecoItem.state, .on, "Manual Eco Mode toggle must check the nested Settings item")

        appDelegate.toggleEcoMode()
        XCTAssertFalse(appDelegate.settings.ecoMode)
        XCTAssertEqual(ecoItem.state, .off, "Manual Eco Mode toggle must uncheck the nested Settings item")
    }

    func testEcoToggle_syncsBrightnessCheckmark_whenLocationSharesSubmenuTitle() {
        let original = appDelegate.weatherManager.savedLocations
        defer { appDelegate.weatherManager.savedLocations = original }
        appDelegate.weatherManager.savedLocations = [SavedLocation(id: UUID(), name: "Brightness", latitude: 0, longitude: 0)]

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        appDelegate.statusItem = statusItem
        appDelegate.menuBarManager.buildMenu(for: statusItem)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        appDelegate.settings.brightness = 1.0
        appDelegate.toggleEcoMode()

        guard let menu = statusItem.menu,
              let halfItem = findMenuItem(title: "50%", in: menu) else {
            return XCTFail("50% brightness item should exist")
        }
        XCTAssertEqual(halfItem.state, .on, "Brightness submenu must sync even when a saved location is named \"Brightness\"")
    }

    private func findMenuItem(title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let submenu = item.submenu, let found = findMenuItem(title: title, in: submenu) {
                return found
            }
        }
        return nil
    }

    // MARK: - Settings Persistence

    func testManualEcoMode_survivesRelaunchAndRestoresBrightness() {
        appDelegate.settings.brightness = 0.75
        appDelegate.toggleEcoMode()

        let relaunched = AppDelegate()
        XCTAssertTrue(relaunched.settings.ecoMode)
        XCTAssertEqual(relaunched.settings.brightness, 0.50, "Eco Mode dims again after relaunch")

        relaunched.toggleEcoMode()
        XCTAssertEqual(relaunched.settings.brightness, 0.75, "Pre-Eco brightness must survive a relaunch")
        XCTAssertFalse(AppDelegate().settings.ecoMode)
    }

    func testAutoEcoMode_isNotPersisted() {
        appDelegate.settings.brightness = 0.75
        // Mirrors the battery monitor, which sets these without a manual toggle.
        appDelegate.settings.ecoMode = true
        appDelegate.settings.brightness = 0.50
        appDelegate.autoEnabledEco = true

        let relaunched = AppDelegate()
        XCTAssertFalse(relaunched.settings.ecoMode)
        XCTAssertEqual(relaunched.settings.brightness, 0.75)
    }

    func testResetToDefaults_clearsPersistedSettings() {
        appDelegate.settings.selectedUnit = .fahrenheit
        appDelegate.settings.showAQI = true
        appDelegate.toggleEcoMode()

        appDelegate.resetToDefaults()

        let relaunched = AppDelegate()
        XCTAssertEqual(relaunched.settings.selectedUnit, .celsius)
        XCTAssertFalse(relaunched.settings.showAQI)
        XCTAssertFalse(relaunched.settings.ecoMode)
        XCTAssertEqual(relaunched.settings.brightness, 1.0)
    }

    func testResetToDefaults_clearsEcoFlags() {
        appDelegate.userDisabledEco = true
        appDelegate.autoEnabledEco = true
        appDelegate.settings.ecoMode = true

        appDelegate.resetToDefaults()

        XCTAssertFalse(appDelegate.settings.ecoMode)
        XCTAssertFalse(appDelegate.userDisabledEco)
        XCTAssertFalse(appDelegate.autoEnabledEco)
    }
}
