import Cocoa
import SwiftUI
import Combine
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var overlayWindows: [NSWindow] = []
    var statusItem: NSStatusItem?
    let weatherManager = WeatherManager()
    let settings = OverlaySettings()
    var isUpdateReady = false
    private var cancellables = Set<AnyCancellable>()

    var menuBarManager: MenuBarManager!
    var updateManager: UpdateManager!

    override init() {
        super.init()
        AppDelegate.shared = self
        self.menuBarManager = MenuBarManager(appDelegate: self, weatherManager: weatherManager, settings: settings)
        self.updateManager = UpdateManager(appDelegate: self)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching started.")
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("WeatherOverlayBackground")

        print("[AppDelegate] Setting up status item and overlay windows...")
        menuBarManager.setup()
        setupOverlayWindows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        print("[AppDelegate] Subscribing to WeatherManager / settings change events...")
        Publishers.Merge(
            weatherManager.objectWillChange.map { _ in () },
            settings.objectWillChange.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.menuBarManager.updateStatusItem() }
        .store(in: &cancellables)

        print("[AppDelegate] Starting the Weather Engine...")
        weatherManager.start()

        performUpdateCheck(isUserInitiated: false)
    }

    private func setupOverlayWindows() {
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let frame = getMenuBarFrame(for: screen)

            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false

            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces]

            let hostingView = NSHostingView(rootView: OverlayView(weatherManager: weatherManager, settings: settings))
            window.contentView = hostingView

            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }
    }

    @objc private func delayedSetupOverlayWindows() {
        setupOverlayWindows()
    }

    private func triggerWindowRecreation() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(delayedSetupOverlayWindows), object: nil)
        self.perform(#selector(delayedSetupOverlayWindows), with: nil, afterDelay: 1.5)
    }

    @objc private func screenParametersChanged() {
        triggerWindowRecreation()
    }

    @objc private func screenDidUnlock() {
        print("[AppDelegate] Screen unlocked notification received. Refreshing weather...")
        weatherManager.fetchWeather()
        triggerWindowRecreation()
    }

    @objc private func systemDidWake() {
        print("[AppDelegate] System did wake notification received. Refreshing weather...")
        weatherManager.fetchWeather()
        triggerWindowRecreation()
    }

    @objc private func systemWillSleep() {
        print("[AppDelegate] System will sleep. Closing windows to prevent Metal GPU crashes...")
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(delayedSetupOverlayWindows), object: nil)
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            do {
                try service.unregister()
                print("[AppDelegate] Unregistered login item successfully.")
            } catch {
                print("[AppDelegate] Failed to unregister login item: \(error)")
            }
        } else {
            do {
                try service.register()
                print("[AppDelegate] Registered login item successfully.")
            } catch {
                print("[AppDelegate] Failed to register login item: \(error)")
                showLoginItemErrorAlert(error)
            }
        }

        menuBarManager.syncMenuStates()
    }

    private func showLoginItemErrorAlert(_ error: Error) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Launch at Login Error"
            alert.informativeText = "Could not register launch at login: \(error.localizedDescription)\n\nPlease make sure the app is in your Applications folder and you have allowed it in System Settings > General > Login Items."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func getMenuBarFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        let menuBarHeight = screenFrame.height - visibleFrame.maxY

        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y + visibleFrame.maxY,
            width: screenFrame.width,
            height: menuBarHeight
        )
    }

    // MARK: - Menu Selectors

    @objc func toggleAurora() {
        settings.showAurora.toggle()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(toggleAurora) }) {
            item.state = settings.showAurora ? .on : .off
        }
    }

    @objc func toggleBottomLine() {
        settings.showBottomLine.toggle()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(toggleBottomLine) }) {
            item.state = settings.showBottomLine ? .on : .off
        }
    }

    @objc func setWeatherUnit(_ sender: NSMenuItem) {
        if let unit = sender.representedObject as? OverlaySettings.WeatherUnit {
            settings.selectedUnit = unit
            menuBarManager.syncUnitSubmenu()
            menuBarManager.updateStatusItem()
        }
    }

    @objc func setBrightness(_ sender: NSMenuItem) {
        if let brightness = sender.representedObject as? Double {
            settings.brightness = brightness
            menuBarManager.syncBrightnessSubmenu()
        }
    }

    @objc func setAuroraStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? OverlaySettings.AuroraStyle {
            settings.manualWeatherCode = style.weatherCode

            if style == .clearDay {
                settings.manualIsNight = false
            } else if style == .clearNight {
                settings.manualIsNight = true
            } else if style == .auto {
                settings.manualIsNight = nil
            }

            menuBarManager.syncAuroraStyleSubmenu()
        }
    }

    @objc func resetToDefaults() {
        settings.showAurora = true
        settings.showBottomLine = false
        settings.selectedUnit = .celsius
        settings.brightness = 1.0
        settings.manualWeatherCode = nil
        settings.manualIsNight = nil

        menuBarManager.syncMenuStates()
        menuBarManager.updateStatusItem()
    }

    @objc func refreshWeather() {
        weatherManager.fetchWeather()
    }

    @objc func promptSetLocation() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Set Location"
        alert.informativeText = "Enter a city name (e.g. \"Mumbai\", \"London\", \"New York\")."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "City name"
        if let current = weatherManager.manualLocation {
            input.stringValue = current.name
        }
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let query = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        print("[AppDelegate] Set Location requested for query: \(query)")
        let manager = weatherManager
        Task.detached {
            do {
                print("[AppDelegate] About to call searchCity...")
                let match = try await manager.searchCity(query)
                print("[AppDelegate] searchCity returned, dispatching to main...")
                DispatchQueue.main.async {
                    print("[AppDelegate] On main thread, processing result...")
                    guard let self = AppDelegate.shared else {
                        print("[AppDelegate] AppDelegate.shared is nil!")
                        return
                    }
                    if let match = match {
                        print("[AppDelegate] Geocoding match: \(match.name) (\(match.latitude), \(match.longitude))")
                        manager.manualLocation = match
                        if let menu = self.statusItem?.menu, menu.items.count > 1 {
                            menu.items[1].title = "Location: \(match.name) (loading...)"
                        }
                        print("[AppDelegate] Calling fetchWeather() for new location...")
                        manager.fetchWeather()
                    } else {
                        print("[AppDelegate] No geocoding match for: \(query)")
                        self.showLocationAlert("No match", "No city found matching \"\(query)\". Try a different spelling.")
                    }
                }
            } catch {
                print("[AppDelegate] Geocoding failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    AppDelegate.shared?.showLocationAlert("Search failed", error.localizedDescription)
                }
            }
        }
    }

    @objc func clearManualLocation() {
        weatherManager.manualLocation = nil
        weatherManager.fetchWeather()
    }

    private func showLocationAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func checkForUpdates() {
        updateManager.performUpdateCheck(isUserInitiated: true)
    }

    @objc func triggerRelaunch() {
        updateManager.relaunchApp()
    }

    private func performUpdateCheck(isUserInitiated: Bool) {
        updateManager.performUpdateCheck(isUserInitiated: isUserInitiated)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
