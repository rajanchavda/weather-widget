import Cocoa
import ServiceManagement

@MainActor
class MenuBarManager {
    unowned let appDelegate: AppDelegate
    unowned let weatherManager: WeatherManager
    unowned let settings: OverlaySettings

    init(appDelegate: AppDelegate, weatherManager: WeatherManager, settings: OverlaySettings) {
        self.appDelegate = appDelegate
        self.weatherManager = weatherManager
        self.settings = settings
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "🌤️ --"
        }
        appDelegate.statusItem = item
        buildMenu(for: item)
    }

    func buildMenu(for statusItem: NSStatusItem) {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Weather Menu Bar Overlay", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let locationItem = NSMenuItem(title: "Location: Detecting...", action: nil, keyEquivalent: "")
        locationItem.isEnabled = false
        menu.addItem(locationItem)

        let setLocationItem = NSMenuItem(title: "Set Location Manually...", action: #selector(AppDelegate.promptSetLocation), keyEquivalent: "")
        setLocationItem.target = appDelegate
        menu.addItem(setLocationItem)

        let autoLocationItem = NSMenuItem(title: "Use Auto Location (IP-based)", action: #selector(AppDelegate.clearManualLocation), keyEquivalent: "")
        autoLocationItem.target = appDelegate
        menu.addItem(autoLocationItem)

        menu.addItem(NSMenuItem.separator())

        let auroraToggle = NSMenuItem(title: "Atmospheric Aurora", action: #selector(AppDelegate.toggleAurora), keyEquivalent: "")
        auroraToggle.target = appDelegate
        auroraToggle.state = settings.showAurora ? .on : .off
        menu.addItem(auroraToggle)

        let lineToggle = NSMenuItem(title: "Bottom Forecast Line", action: #selector(AppDelegate.toggleBottomLine), keyEquivalent: "")
        lineToggle.target = appDelegate
        lineToggle.state = settings.showBottomLine ? .on : .off
        menu.addItem(lineToggle)

        let unitMenu = NSMenu()
        for unit in OverlaySettings.WeatherUnit.allCases {
            let item = NSMenuItem(title: "Use \(unit.rawValue)", action: #selector(AppDelegate.setWeatherUnit(_:)), keyEquivalent: "")
            item.target = appDelegate
            item.representedObject = unit
            item.state = settings.selectedUnit == unit ? .on : .off
            unitMenu.addItem(item)
        }
        let unitItem = NSMenuItem(title: "Temperature Unit", action: nil, keyEquivalent: "")
        unitItem.submenu = unitMenu
        menu.addItem(unitItem)

        let displayModeMenu = NSMenu()
        for mode in OverlaySettings.StatusBarDisplayMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(AppDelegate.setDisplayMode(_:)), keyEquivalent: "")
            item.target = appDelegate
            item.representedObject = mode
            item.state = settings.displayMode == mode ? .on : .off
            displayModeMenu.addItem(item)
        }
        let displayModeItem = NSMenuItem(title: "Status Bar Display", action: nil, keyEquivalent: "")
        displayModeItem.submenu = displayModeMenu
        menu.addItem(displayModeItem)

        let brightnessMenu = NSMenu()
        let brightnessLevels: [(String, Double)] = [
            ("100%", 1.0), ("75%", 0.75), ("50%", 0.5), ("25%", 0.25)
        ]
        for level in brightnessLevels {
            let item = NSMenuItem(title: level.0, action: #selector(AppDelegate.setBrightness(_:)), keyEquivalent: "")
            item.target = appDelegate
            item.representedObject = level.1
            item.state = abs(settings.brightness - level.1) < 0.01 ? .on : .off
            brightnessMenu.addItem(item)
        }
        let brightnessItem = NSMenuItem(title: "Brightness", action: nil, keyEquivalent: "")
        brightnessItem.submenu = brightnessMenu
        menu.addItem(brightnessItem)

        let auroraStyleMenu = NSMenu()
        for style in OverlaySettings.AuroraStyle.allCases {
            let item = NSMenuItem(title: style.rawValue, action: #selector(AppDelegate.setAuroraStyle(_:)), keyEquivalent: "")
            item.target = appDelegate
            item.representedObject = style
            item.state = isStyleSelected(style) ? .on : .off
            auroraStyleMenu.addItem(item)
        }
        let auroraStyleItem = NSMenuItem(title: "Try Different Aurora", action: nil, keyEquivalent: "")
        auroraStyleItem.submenu = auroraStyleMenu
        menu.addItem(auroraStyleItem)

        let launchToggle = NSMenuItem(title: "Launch at Login", action: #selector(AppDelegate.toggleLaunchAtLogin), keyEquivalent: "")
        launchToggle.target = appDelegate
        launchToggle.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchToggle)

        menu.addItem(NSMenuItem.separator())

        let resetItem = NSMenuItem(title: "Reset to Defaults", action: #selector(AppDelegate.resetToDefaults), keyEquivalent: "")
        resetItem.target = appDelegate
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Force Refresh Weather", action: #selector(AppDelegate.refreshWeather), keyEquivalent: "r")
        refreshItem.target = appDelegate
        menu.addItem(refreshItem)

        let updateItem = NSMenuItem(title: "Check for Updates", action: #selector(AppDelegate.checkForUpdates), keyEquivalent: "")
        updateItem.target = appDelegate
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(title: "About Weather Overlay", action: #selector(AppDelegate.showAbout), keyEquivalent: "")
        aboutItem.target = appDelegate
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Weather Overlay", action: #selector(AppDelegate.quitApp), keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateStatusItem() {
        updateStatusItem(
            temp: weatherManager.currentTemp,
            code: weatherManager.weatherCode,
            city: weatherManager.cityName,
            hasData: weatherManager.hasData,
            error: weatherManager.errorMessage
        )
    }

    func updateStatusItem(temp: Double, code: Int, city: String, hasData: Bool, error: String?) {
        guard let button = appDelegate.statusItem?.button else { return }

        let title: String
        let locationTitle: String

        if let error = error {
            title = "⚠️ Err"
            locationTitle = "Error: \(error)"
        } else if !hasData {
            title = "🌤️ --"
            locationTitle = "Location: Detecting..."
        } else {
            let emoji = getWeatherEmoji(code)
            let displayedTemp: Double
            if settings.selectedUnit == .fahrenheit {
                displayedTemp = temp * 9.0 / 5.0 + 32.0
            } else {
                displayedTemp = temp
            }
            title = buildStatusTitle(emoji: emoji, displayedTemp: displayedTemp)
            locationTitle = "Location: \(city)"
        }

        if appDelegate.isUpdateReady {
            button.title = title + " ⚠️"
        } else {
            button.title = title
        }

        if let menu = appDelegate.statusItem?.menu, menu.items.count > 1 {
            menu.items[1].title = locationTitle
        }
    }

    private func getWeatherEmoji(_ code: Int) -> String {
        let isNight = checkIsNight()

        switch code {
        case 0, 1: return isNight ? "🌙" : "☀️"
        case 2, 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51...67: return "🌧️"
        case 71...77: return "❄️"
        case 80...82: return "🌦️"
        case 85...86: return "🌨️"
        case 95...99: return "⛈️"
        default: return "🌤️"
        }
    }

    private func buildStatusTitle(emoji: String, displayedTemp: Double) -> String {
        switch settings.displayMode {
        case .iconAndTemp:
            return String(format: "%@ %.1f%@", emoji, displayedTemp, settings.selectedUnit.rawValue)
        case .iconOnly:
            return emoji
        case .tempOnly:
            return String(format: "%.1f%@", displayedTemp, settings.selectedUnit.rawValue)
        }
    }

    private func checkIsNight() -> Bool {
        if let manualIsNight = settings.manualIsNight {
            return manualIsNight
        }
        return weatherManager.isNight
    }

    private func isStyleSelected(_ style: OverlaySettings.AuroraStyle) -> Bool {
        if style == .auto {
            return settings.manualWeatherCode == nil
        } else if style == .clearDay {
            return settings.manualWeatherCode == 0 && settings.manualIsNight == false
        } else if style == .clearNight {
            return settings.manualWeatherCode == 0 && settings.manualIsNight == true
        } else {
            return style.weatherCode == settings.manualWeatherCode
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    func syncMenuStates() {
        guard let menu = appDelegate.statusItem?.menu else { return }

        if let auroraItem = menu.items.first(where: { $0.action == #selector(AppDelegate.toggleAurora) }) {
            auroraItem.state = settings.showAurora ? .on : .off
        }

        if let launchItem = menu.items.first(where: { $0.action == #selector(AppDelegate.toggleLaunchAtLogin) }) {
            launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        }

        if let lineItem = menu.items.first(where: { $0.action == #selector(AppDelegate.toggleBottomLine) }) {
            lineItem.state = settings.showBottomLine ? .on : .off
        }

        for item in menu.items where item.title == "Temperature Unit" {
            if let submenu = item.submenu {
                for unitItem in submenu.items {
                    unitItem.state = (unitItem.representedObject as? OverlaySettings.WeatherUnit) == settings.selectedUnit ? .on : .off
                }
            }
        }

        for item in menu.items where item.title == "Brightness" {
            if let submenu = item.submenu {
                for brightnessItem in submenu.items {
                    if let brightness = brightnessItem.representedObject as? Double {
                        brightnessItem.state = abs(brightness - settings.brightness) < 0.01 ? .on : .off
                    }
                }
            }
        }

        for item in menu.items where item.title == "Try Different Aurora" {
            if let submenu = item.submenu {
                for styleItem in submenu.items {
                    if let style = styleItem.representedObject as? OverlaySettings.AuroraStyle {
                        styleItem.state = isStyleSelected(style) ? .on : .off
                    }
                }
            }
        }

        syncDisplayModeSubmenu()
    }

    func syncUnitSubmenu() {
        guard let menu = appDelegate.statusItem?.menu else { return }
        for item in menu.items where item.title == "Temperature Unit" {
            if let submenu = item.submenu {
                for unitItem in submenu.items {
                    unitItem.state = (unitItem.representedObject as? OverlaySettings.WeatherUnit) == settings.selectedUnit ? .on : .off
                }
            }
        }
    }

    func syncBrightnessSubmenu() {
        guard let menu = appDelegate.statusItem?.menu else { return }
        for item in menu.items where item.title == "Brightness" {
            if let submenu = item.submenu {
                for brightnessItem in submenu.items {
                    if let brightness = brightnessItem.representedObject as? Double {
                        brightnessItem.state = abs(brightness - settings.brightness) < 0.01 ? .on : .off
                    }
                }
            }
        }
    }

    func syncAuroraStyleSubmenu() {
        guard let menu = appDelegate.statusItem?.menu else { return }
        for item in menu.items where item.title == "Try Different Aurora" {
            if let submenu = item.submenu {
                for styleItem in submenu.items {
                    if let style = styleItem.representedObject as? OverlaySettings.AuroraStyle {
                        styleItem.state = isStyleSelected(style) ? .on : .off
                    }
                }
            }
        }
    }

    func syncDisplayModeSubmenu() {
        guard let menu = appDelegate.statusItem?.menu else { return }
        for item in menu.items where item.title == "Status Bar Display" {
            if let submenu = item.submenu {
                for modeItem in submenu.items {
                    if let mode = modeItem.representedObject as? OverlaySettings.StatusBarDisplayMode {
                        modeItem.state = mode == settings.displayMode ? .on : .off
                    }
                }
            }
        }
    }
}
