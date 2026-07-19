import XCTest
import Cocoa
@testable import WeatherOverlayCore

@MainActor
final class MenuBarManagerTests: XCTestCase {
    var appDelegate: MockAppDelegate!
    var menuBarManager: MenuBarManager!
    var weatherManager: WeatherManager!
    var settings: OverlaySettings!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "WeatherOverlay.savedLocations")
        UserDefaults.standard.removeObject(forKey: "WeatherOverlay.manualLocation")
        UserDefaults.standard.removeObject(forKey: "WeatherOverlay.activeLocationId")
        weatherManager = WeatherManager(session: .mock)
        settings = OverlaySettings()
        appDelegate = MockAppDelegate()
        menuBarManager = MenuBarManager(
            appDelegate: appDelegate,
            weatherManager: weatherManager,
            settings: settings
        )
    }

    override func tearDown() async throws {
        menuBarManager = nil
        appDelegate = nil
        weatherManager = nil
        settings = nil
        try await super.tearDown()
    }

    // MARK: - Status Item Text Formatting

    func testStatusItemText_celsiusClearDay() {
        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("22.0"))
        XCTAssertTrue(title.contains("°C"))
    }

    func testStatusItemText_fahrenheit() {
        settings.selectedUnit = .fahrenheit

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("71.6"))
        XCTAssertTrue(title.contains("°F"))
    }

    func testStatusItemText_clearNight() {
        weatherManager.isNight = true

        menuBarManager.updateStatusItem(temp: 15.0, code: 0, city: "Paris", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌙"))
    }

    func testStatusItemText_clearDay_emoji() {
        menuBarManager.updateStatusItem(temp: 20.0, code: 0, city: "Mumbai", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("☀️"))
    }

    func testStatusItemText_cloudy() {
        menuBarManager.updateStatusItem(temp: 18.0, code: 3, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("☁️"))
    }

    func testStatusItemText_fog() {
        menuBarManager.updateStatusItem(temp: 10.0, code: 45, city: "Berlin", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌫️"))
    }

    func testStatusItemText_rain() {
        menuBarManager.updateStatusItem(temp: 12.0, code: 61, city: "Tokyo", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌧️"))
    }

    func testStatusItemText_drizzle() {
        menuBarManager.updateStatusItem(temp: 14.0, code: 51, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌧️"), "Drizzle (code 51) should still show rain emoji")
    }

    func testStatusItemText_snow() {
        menuBarManager.updateStatusItem(temp: -2.0, code: 73, city: "Oslo", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("❄️"))
        XCTAssertTrue(title.contains("-2.0"))
    }

    func testStatusItemText_showers() {
        menuBarManager.updateStatusItem(temp: 14.0, code: 80, city: "Sydney", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌦️"))
    }

    func testStatusItemText_snowShowers() {
        menuBarManager.updateStatusItem(temp: 0.0, code: 85, city: "Zurich", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌨️"))
    }

    func testStatusItemText_thunderstorm() {
        menuBarManager.updateStatusItem(temp: 25.0, code: 96, city: "Miami", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("⛈️"))
    }

    func testStatusItemText_noData() {
        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertEqual(title, "🌤️ --")
    }

    func testStatusItemText_errorState() {
        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: "Network error")

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertEqual(title, "⚠️ Err")
    }

    func testStatusItemText_updateReady() {
        appDelegate.isUpdateReady = true

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("⚠️"))
    }

    // MARK: - Display Mode

    func testStatusItemText_iconOnly() {
        settings.displayMode = .iconOnly

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("☀️"))
        XCTAssertFalse(title.contains("22.0"))
        XCTAssertFalse(title.contains("°C"))
    }

    func testStatusItemText_tempOnly() {
        settings.displayMode = .tempOnly

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("22.0"))
        XCTAssertTrue(title.contains("°C"))
        XCTAssertFalse(title.contains("☀️"))
    }

    func testStatusItemText_iconOnly_updateReady() {
        settings.displayMode = .iconOnly
        appDelegate.isUpdateReady = true

        menuBarManager.updateStatusItem(temp: 15.0, code: 0, city: "Paris", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("☀️"))
        XCTAssertTrue(title.contains("⚠️"))
        XCTAssertFalse(title.contains("15.0"))
    }

    func testStatusItemText_tempOnly_updateReady() {
        settings.displayMode = .tempOnly
        appDelegate.isUpdateReady = true

        menuBarManager.updateStatusItem(temp: 10.0, code: 3, city: "Berlin", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("10.0"))
        XCTAssertTrue(title.contains("⚠️"))
        XCTAssertFalse(title.contains("☁️"))
    }

    func testStatusItemText_errorState_iconOnly() {
        settings.displayMode = .iconOnly

        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: "Network error")

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertEqual(title, "⚠️ Err")
    }

    func testStatusItemText_noData_tempOnly() {
        settings.displayMode = .tempOnly

        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertEqual(title, "🌤️ --")
    }

    // MARK: - Location Title

    func testLocationTitleUpdate() {
        menuBarManager.updateStatusItem(temp: 20.0, code: 0, city: "Tokyo", hasData: true, error: nil)

        let locationTitle = appDelegate.statusItem?.menu?.items[0].title ?? ""
        XCTAssertEqual(locationTitle, "Location: Tokyo")
        
        let conditionTitle = appDelegate.statusItem?.menu?.items[1].title ?? ""
        XCTAssertEqual(conditionTitle, "Condition: 20.0°C • Clear Sky")
    }

    func testLocationTitleErrorState() {
        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: "Timeout")

        let locationTitle = appDelegate.statusItem?.menu?.items[0].title ?? ""
        XCTAssertEqual(locationTitle, "Error: Timeout")
        
        let conditionTitle = appDelegate.statusItem?.menu?.items[1].title ?? ""
        XCTAssertEqual(conditionTitle, "Condition: --")
    }

    func testLocationTitleNoData() {
        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: nil)

        let locationTitle = appDelegate.statusItem?.menu?.items[0].title ?? ""
        XCTAssertEqual(locationTitle, "Location: Detecting...")
        
        let conditionTitle = appDelegate.statusItem?.menu?.items[1].title ?? ""
        XCTAssertEqual(conditionTitle, "Condition: --")
    }

    // MARK: - Temperature Rounding

    func testStatusItemText_temperatureRounding() {
        menuBarManager.updateStatusItem(temp: 22.67, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("22.7"))
    }

    func testStatusItemText_fahrenheitRounding() {
        settings.selectedUnit = .fahrenheit

        menuBarManager.updateStatusItem(temp: 10.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("50.0"))
    }

    // MARK: - Eco Mode

    func testStatusItemText_ecoModeShowsLeaf() {
        settings.ecoMode = true

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌱"))
        XCTAssertTrue(title.contains("22.0"))
    }

    func testStatusItemText_ecoModeLeafNotShownWhenOff() {
        settings.ecoMode = false

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertFalse(title.contains("🌱"))
    }

    func testStatusItemText_ecoModeWithUpdateReady() {
        settings.ecoMode = true
        appDelegate.isUpdateReady = true

        menuBarManager.updateStatusItem(temp: 15.0, code: 0, city: "Paris", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌱"))
        XCTAssertTrue(title.contains("⚠️"))
    }

    func testStatusItemText_ecoModeIconOnly() {
        settings.displayMode = .iconOnly
        settings.ecoMode = true

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("🌱"))
        XCTAssertTrue(title.contains("☀️"))
        XCTAssertFalse(title.contains("22.0"))
    }

    func testStatusItemText_ecoModeNoData() {
        settings.ecoMode = true

        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertEqual(title, "🌤️ -- 🌱")
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

    func testEcoModeMenuItemExists() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let ecoItem = findMenuItem(title: "Eco Mode", in: menu)
        XCTAssertNotNil(ecoItem)
    }

    func testEcoModeMenuItemState_on() {
        settings.ecoMode = true
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let ecoItem = findMenuItem(title: "Eco Mode", in: menu)
        XCTAssertEqual(ecoItem?.state, NSControl.StateValue.on)
    }

    func testEcoModeMenuItemState_off() {
        settings.ecoMode = false
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let ecoItem = findMenuItem(title: "Eco Mode", in: menu)
        XCTAssertEqual(ecoItem?.state, NSControl.StateValue.off)
    }

    func testEcoModeMenuItemTargetIsAppDelegate() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let ecoItem = findMenuItem(title: "Eco Mode", in: menu)
        XCTAssertTrue(ecoItem?.target is AppDelegate)
    }

    func testEcoModeMenuItemAction() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let ecoItem = findMenuItem(title: "Eco Mode", in: menu)
        XCTAssertEqual(ecoItem?.action, #selector(AppDelegate.toggleEcoMode))
    }

    // MARK: - AQI Display

    func testAQINotShownByDefault() {
        weatherManager.aqiValue = 42
        weatherManager.aqiLabel = "Fair"

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertFalse(title.contains("AQI"))
    }

    func testAQIShownWhenEnabled() {
        settings.showAQI = true
        weatherManager.aqiValue = 42
        weatherManager.aqiLabel = "Fair"

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("AQI: 42"))
        XCTAssertTrue(title.contains("Fair"))
        XCTAssertTrue(title.contains("22.0"))
    }

    func testAQIWithEcoMode() {
        settings.showAQI = true
        settings.ecoMode = true
        weatherManager.aqiValue = 12
        weatherManager.aqiLabel = "Good"

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("AQI: 12"))
        XCTAssertTrue(title.contains("Good"))
        XCTAssertTrue(title.contains("🌱"))
    }

    func testAQIWithUpdateReady() {
        settings.showAQI = true
        appDelegate.isUpdateReady = true
        weatherManager.aqiValue = 55
        weatherManager.aqiLabel = "Moderate"

        menuBarManager.updateStatusItem(temp: 15.0, code: 0, city: "Paris", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("AQI: 55"))
        XCTAssertTrue(title.contains("⚠️"))
    }

    func testAQIIconOnly() {
        settings.showAQI = true
        settings.displayMode = .iconOnly
        weatherManager.aqiValue = 30
        weatherManager.aqiLabel = "Fair"

        menuBarManager.updateStatusItem(temp: 22.0, code: 0, city: "London", hasData: true, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertTrue(title.contains("☀️"))
        XCTAssertTrue(title.contains("AQI: 30"))
        XCTAssertFalse(title.contains("22.0"))
    }

    func testAQINotShownWhenNoData() {
        settings.showAQI = true
        weatherManager.aqiValue = nil
        weatherManager.aqiLabel = ""

        menuBarManager.updateStatusItem(temp: 0.0, code: 0, city: "Detecting...", hasData: false, error: nil)

        let title = appDelegate.statusItem?.button?.title ?? ""
        XCTAssertEqual(title, "🌤️ --")
        XCTAssertFalse(title.contains("AQI"))
    }

    private func findAQIMenuItem() -> NSMenuItem? {
        guard let menu = appDelegate.statusItem?.menu else { return nil }
        return findMenuItem(title: "Show Air Quality Index", in: menu)
    }

    func testAQIToggleMenuItemExists() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        XCTAssertNotNil(findAQIMenuItem())
    }

    func testAQIToggleMenuItemTargetIsAppDelegate() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let aqiItem = findAQIMenuItem()
        XCTAssertTrue(aqiItem?.target is AppDelegate)
    }

    func testAQIToggleMenuItemAction() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let aqiItem = findAQIMenuItem()
        XCTAssertEqual(aqiItem?.action, #selector(AppDelegate.toggleAQI))
    }

    func testAQIToggleMenuItemState_off() {
        settings.showAQI = false
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let aqiItem = findAQIMenuItem()
        XCTAssertEqual(aqiItem?.state, NSControl.StateValue.off)
    }

    func testAQIToggleMenuItemState_on() {
        settings.showAQI = true
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let aqiItem = findAQIMenuItem()
        XCTAssertEqual(aqiItem?.state, NSControl.StateValue.on)
    }

    // MARK: - About Menu Item

    func testAboutMenuItemExists() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let aboutItem = menu.items.first(where: { $0.title == "About Weather Overlay" })
        XCTAssertNotNil(aboutItem)
    }

    func testAboutMenuItemIsSecondToLast() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let items = menu.items
        let quitIndex = items.lastIndex(where: { $0.title == "Quit Weather Overlay" }) ?? -1
        let aboutIndex = items.lastIndex(where: { $0.title == "About Weather Overlay" }) ?? -2

        XCTAssertGreaterThan(quitIndex, 0)
        XCTAssertEqual(aboutIndex, quitIndex - 1)
    }

    func testAboutMenuItemHasAction() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let aboutItem = menu.items.first(where: { $0.title == "About Weather Overlay" })
        XCTAssertNotNil(aboutItem?.action)
        XCTAssertEqual(aboutItem?.action, #selector(AppDelegate.showAbout))
    }

    func testAboutMenuItemTargetIsAppDelegate() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let aboutItem = menu.items.first(where: { $0.title == "About Weather Overlay" })
        XCTAssertTrue(aboutItem?.target is AppDelegate)
    }

    // MARK: - Locations Submenu

    func testLocationsSubmenuExists() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        let locationsItem = menu.items.first(where: { $0.title == "Locations" })
        XCTAssertNotNil(locationsItem)
        XCTAssertNotNil(locationsItem?.submenu)
    }

    func testLocationsSubmenu_autoLocationItem() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let autoItem = submenu.items.first
        XCTAssertEqual(autoItem?.title, "Auto (IP-based)")
        XCTAssertEqual(autoItem?.action, #selector(AppDelegate.switchToAutoLocation))
        XCTAssertTrue(autoItem?.target is AppDelegate)
    }

    func testLocationsSubmenu_addLocationItem() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let addItem = submenu.items.first(where: { $0.title == "Add Location..." })
        XCTAssertNotNil(addItem)
        XCTAssertEqual(addItem?.action, #selector(AppDelegate.addLocation))
        XCTAssertTrue(addItem?.target is AppDelegate)
    }

    func testLocationsSubmenu_removeLocationItem() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let removeItem = submenu.items.first(where: { $0.title == "Remove Location..." })
        XCTAssertNotNil(removeItem)
        XCTAssertEqual(removeItem?.action, #selector(AppDelegate.removeLocation))
        XCTAssertTrue(removeItem?.target is AppDelegate)
    }

    func testLocationsSubmenu_autoIsCheckedWhenNoActiveLocation() {
        weatherManager.activeLocationId = nil
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let autoItem = submenu.items.first
        XCTAssertEqual(autoItem?.state, NSControl.StateValue.on)
    }

    func testLocationsSubmenu_autoIsUncheckedWhenActiveLocation() {
        let saved = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)
        weatherManager.savedLocations = [saved]
        weatherManager.activeLocationId = saved.id
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let autoItem = submenu.items.first
        XCTAssertEqual(autoItem?.state, NSControl.StateValue.off)
    }

    func testLocationsSubmenu_savedLocationItemsHaveCorrectAction() {
        let saved = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)
        weatherManager.savedLocations = [saved]
        weatherManager.activeLocationId = saved.id
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let savedItem = submenu.items.first(where: { $0.title == "Paris" })
        XCTAssertNotNil(savedItem)
        XCTAssertEqual(savedItem?.action, #selector(AppDelegate.switchToSavedLocation))
        XCTAssertTrue(savedItem?.target is AppDelegate)
        if let repoSaved = savedItem?.representedObject as? SavedLocation {
            XCTAssertEqual(repoSaved.id, saved.id)
            XCTAssertEqual(repoSaved.name, "Paris")
        } else {
            XCTFail("SavedLocation not passed as representedObject")
        }
    }

    func testLocationsSubmenu_activeLocationPersistedOnRestart() {
        let saved = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)
        SavedLocation.saveAll([saved])
        UserDefaults.standard.set(saved.id.uuidString, forKey: "WeatherOverlay.activeLocationId")

        let freshManager = WeatherManager(session: .mock)
        XCTAssertEqual(freshManager.activeLocationId, saved.id, "activeLocationId restored from UserDefaults")
        XCTAssertEqual(freshManager.savedLocations.count, 1)

        let freshDelegate = MockAppDelegate()
        let freshSettings = OverlaySettings()
        let freshMenuBar = MenuBarManager(appDelegate: freshDelegate, weatherManager: freshManager, settings: freshSettings)
        freshMenuBar.buildMenu(for: freshDelegate.statusItem!)

        let menu = freshDelegate.statusItem!.menu!
        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let autoItem = submenu.items.first
        XCTAssertEqual(autoItem?.state, NSControl.StateValue.off, "Auto should be unchecked when a saved location is active")

        let parisItem = submenu.items.first(where: { $0.title == "Paris" })
        XCTAssertNotNil(parisItem)
        XCTAssertEqual(parisItem?.state, NSControl.StateValue.on)

        freshMenuBar.syncLocationsSubmenu()
        let updatedSubmenu = locationsItem.submenu
        let updatedAutoItem = updatedSubmenu?.items.first
        XCTAssertEqual(updatedAutoItem?.state, NSControl.StateValue.off, "Auto still unchecked after sync")
        let updatedParisItem = updatedSubmenu?.items.first(where: { $0.title == "Paris" })
        XCTAssertEqual(updatedParisItem?.state, NSControl.StateValue.on)

        _ = freshMenuBar
        _ = freshDelegate
        _ = freshManager
        _ = freshSettings
    }

    func testLocationsSubmenu_activeLocationIsChecked() {
        let paris = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)
        let london = SavedLocation(id: UUID(), name: "London", latitude: 51.5074, longitude: -0.1278)
        weatherManager.savedLocations = [paris, london]
        weatherManager.activeLocationId = paris.id
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let parisItem = submenu.items.first(where: { $0.title == "Paris" })
        let londonItem = submenu.items.first(where: { $0.title == "London" })
        XCTAssertEqual(parisItem?.state, NSControl.StateValue.on)
        XCTAssertEqual(londonItem?.state, NSControl.StateValue.off)
    }

    func testLocationsSubmenu_syncAfterAddingLocation() {
        let saved = SavedLocation(id: UUID(), name: "Tokyo", latitude: 35.6762, longitude: 139.6503)
        weatherManager.savedLocations = [saved]
        weatherManager.activeLocationId = saved.id
        menuBarManager.buildMenu(for: appDelegate.statusItem!)

        menuBarManager.syncLocationsSubmenu()
        let menu = appDelegate.statusItem!.menu!

        guard let locationsItem = menu.items.first(where: { $0.title == "Locations" }),
              let submenu = locationsItem.submenu else {
            XCTFail("Locations submenu not found"); return
        }

        let tokyoItem = submenu.items.first(where: { $0.title == "Tokyo" })
        XCTAssertNotNil(tokyoItem)
        XCTAssertEqual(tokyoItem?.state, NSControl.StateValue.on)
        let autoItem = submenu.items.first
        XCTAssertEqual(autoItem?.state, NSControl.StateValue.off)
    }

    // MARK: - Delegate Tests
    
    func testMenuDelegatesAssigned() {
        menuBarManager.buildMenu(for: appDelegate.statusItem!)
        guard let menu = appDelegate.statusItem?.menu else {
            XCTFail("Menu should exist")
            return
        }
        
        let auroraItem = findMenuItem(title: "Try Different Aurora", in: menu)
        XCTAssertNotNil(auroraItem?.submenu?.delegate, "Aurora submenu delegate should be set")
    }

    // MARK: - Menu Bar Layout Sync

    func testSyncDisplayModeSubmenu_updatesCheckmarks() {
        settings.displayMode = .iconAndTemp
        menuBarManager.buildMenu(for: appDelegate.statusItem!)

        settings.displayMode = .tempOnly
        menuBarManager.syncDisplayModeSubmenu()

        let menu = appDelegate.statusItem!.menu!
        let layoutItem = findMenuItem(title: "Menu Bar Layout", in: menu)
        XCTAssertNotNil(layoutItem?.submenu, "Menu Bar Layout submenu must be findable for sync")

        let tempOnlyItem = layoutItem?.submenu?.items.first(where: {
            ($0.representedObject as? OverlaySettings.StatusBarDisplayMode) == .tempOnly
        })
        let iconAndTempItem = layoutItem?.submenu?.items.first(where: {
            ($0.representedObject as? OverlaySettings.StatusBarDisplayMode) == .iconAndTemp
        })
        XCTAssertEqual(tempOnlyItem?.state, NSControl.StateValue.on)
        XCTAssertEqual(iconAndTempItem?.state, NSControl.StateValue.off)
    }
}

@MainActor
class MockAppDelegate: AppDelegate {
    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.menu = NSMenu()

        let locationItem = NSMenuItem(title: "Location: Detecting...", action: nil, keyEquivalent: "")
        locationItem.tag = 1001
        statusItem?.menu?.addItem(locationItem)

        let conditionItem = NSMenuItem(title: "Condition: --", action: nil, keyEquivalent: "")
        conditionItem.tag = 1002
        statusItem?.menu?.addItem(conditionItem)
    }
}
