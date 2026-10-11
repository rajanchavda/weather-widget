import Cocoa
import SwiftUI
import Combine
import ServiceManagement
import IOKit.ps
import os

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var overlayWindows: [NSWindow] = []
    var statusItem: NSStatusItem?
    let weatherManager = WeatherManager()
    let settings = OverlaySettings(defaults: .standard)
    var isUpdateReady = false
    var userDisabledEco = false
    /// True only when Eco Mode was turned on automatically by the battery monitor.
    /// Manual Eco Mode is left alone when power state recovers.
    var autoEnabledEco = false
    /// Brightness to restore when Eco Mode ends; nil if the user picked a level while Eco was on.
    var brightnessBeforeEco: Double?
    private var cancellables = Set<AnyCancellable>()
    private var batteryCheckTimer: Timer?

    var menuBarManager: MenuBarManager!
    var updateManager: UpdateManager!
    var notificationManager: NotificationManager!

    public override init() {
        self.notificationManager = NotificationManager(weatherManager: weatherManager, settings: settings)
        super.init()
        AppDelegate.shared = self
        // A stored manual Eco Mode comes back with the user's full brightness; dim it again.
        if settings.ecoMode {
            brightnessBeforeEco = settings.brightness
            settings.brightness = min(settings.brightness, 0.50)
        }
        self.menuBarManager = MenuBarManager(appDelegate: self, weatherManager: weatherManager, settings: settings)
        self.updateManager = UpdateManager(appDelegate: self)
    }

    deinit {
        batteryCheckTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("applicationDidFinishLaunching started.")
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("WeatherOverlayBackground")

        Log.app.info("Setting up status item and overlay windows...")
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        Log.app.info("Requesting notification authorization...")
        notificationManager.requestAuthorization()

        Log.app.info("Subscribing to WeatherManager / settings change events...")
        observeChanges { [weak self] in
            guard let self = self else { return }
            self.menuBarManager.updateStatusItem()
            self.menuBarManager.syncLocationsSubmenu()
            self.notificationManager.evaluateAndNotify()
        }
        .store(in: &cancellables)

        Log.app.info("Starting the Weather Engine...")
        weatherManager.start()

        setupPowerMonitoring()

        performUpdateCheck(isUserInitiated: false)
    }

    /// A single fetch changes a dozen published properties in a row; wait for the burst
    /// to settle so the status item, menu and alerts are refreshed once, not once each.
    static let changeDebounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(50)

    func observeChanges(_ handler: @escaping () -> Void) -> AnyCancellable {
        Publishers.Merge(
            weatherManager.objectWillChange.map { _ in () },
            settings.objectWillChange.map { _ in () }
        )
        .debounce(for: Self.changeDebounce, scheduler: RunLoop.main)
        .sink(receiveValue: handler)
    }

    func setupOverlayWindows() {
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let frame = getMenuBarFrame(for: screen)
            guard frame.height > 1 else { continue }
            overlayWindows.append(makeOverlayWindow(frame: frame))
        }
    }

    private func makeOverlayWindow(frame: NSRect) -> NSWindow {
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
        // Avoid `.canJoinAllSpaces` so the overlay does not float over other apps'
        // fullscreen spaces (e.g. VLC). `.moveToActiveSpace` keeps it on normal desktops.
        // Do not use `.stationary` — it can keep high-level windows visible across
        // fullscreen Space transitions.
        window.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]

        let hostingView = NSHostingView(rootView: OverlayView(weatherManager: weatherManager, settings: settings))
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Brings the existing overlay windows to the active Space, keeping their views and
    /// running animations. A window is rebuilt only if it did not follow the switch.
    /// Screens with no menu bar (fullscreen) lose their window.
    func syncOverlayWindowsToActiveSpace() {
        var remaining = overlayWindows
        var synced: [NSWindow] = []

        for screen in NSScreen.screens {
            let frame = getMenuBarFrame(for: screen)
            guard frame.height > 1 else { continue }

            if let index = remaining.firstIndex(where: { $0.frame == frame }) {
                let window = remaining.remove(at: index)
                window.orderFrontRegardless()
                if window.isOnActiveSpace {
                    synced.append(window)
                    continue
                }
                window.close()
            }
            synced.append(makeOverlayWindow(frame: frame))
        }

        for window in remaining {
            window.close()
        }
        overlayWindows = synced
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

    @objc private func activeSpaceDidChange() {
        // `moveToActiveSpace` does not reliably relocate these click-through overlay
        // windows on desktop switches by itself, so pull them over explicitly.
        // If geometry is mid-transition and nothing was created, retry after settle.
        guard !weatherManager.isPaused else { return }
        syncOverlayWindowsToActiveSpace()
        if overlayWindows.isEmpty {
            triggerWindowRecreation()
        }
    }

    @objc private func screenDidUnlock() {
        Log.app.info("Screen unlocked notification received. Refreshing weather...")
        weatherManager.fetchWeather()
        triggerWindowRecreation()
    }

    @objc private func systemDidWake() {
        Log.app.info("System did wake notification received.")
        resumeAll()
    }

    @objc private func systemWillSleep() {
        Log.app.info("System will sleep.")
        pauseAll()
    }

    @objc private func displayDidSleep() {
        Log.app.info("Display did sleep.")
        pauseAll()
    }

    @objc private func displayDidWake() {
        Log.app.info("Display did wake.")
        resumeAll()
    }

    @objc private func sessionDidResignActive() {
        Log.app.info("Session did resign active.")
        pauseAll()
    }

    @objc private func sessionDidBecomeActive() {
        Log.app.info("Session did become active.")
        resumeAll()
    }

    private func pauseAll() {
        weatherManager.pause()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(delayedSetupOverlayWindows), object: nil)
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
    }

    private func resumeAll() {
        weatherManager.resume()
        setupOverlayWindows()
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            do {
                try service.unregister()
                Log.app.notice("Unregistered login item successfully.")
            } catch {
                Log.app.error("Failed to unregister login item: \(String(describing: error), privacy: .public)")
            }
        } else {
            do {
                try service.register()
                Log.app.notice("Registered login item successfully.")
            } catch {
                Log.app.error("Failed to register login item: \(String(describing: error), privacy: .public)")
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
        let menuBarHeight = (screenFrame.origin.y + screenFrame.height) - visibleFrame.maxY

        return NSRect(
            x: screenFrame.origin.x,
            y: visibleFrame.maxY,
            width: screenFrame.width,
            height: menuBarHeight
        )
    }

    // MARK: - Power / Eco Mode

    private func setupPowerMonitoring() {
        batteryCheckTimer?.invalidate()
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkBatteryAndUpdateEcoMode()
            }
        }
        checkBatteryAndUpdateEcoMode()
    }

    private func checkBatteryAndUpdateEcoMode() {
        let (onBattery, percent) = getBatteryState()

        if !onBattery || percent > 20 {
            userDisabledEco = false
            // Only auto-disable when Eco was turned on by the battery monitor.
            if autoEnabledEco && settings.ecoMode {
                exitEcoMode()
                autoEnabledEco = false
                menuBarManager.syncMenuStates()
                menuBarManager.updateStatusItem()
            }
        }

        if onBattery && percent <= 20 && !userDisabledEco {
            if !settings.ecoMode {
                Log.app.notice("Battery \(percent, privacy: .public)% — auto-enabling Eco Mode")
                enterEcoMode()
                autoEnabledEco = true
                menuBarManager.syncMenuStates()
                menuBarManager.updateStatusItem()
            }
        }
    }

    private func getBatteryState() -> (onBattery: Bool, percent: Int) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (false, 100)
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [AnyObject] else {
            return (false, 100)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            // Skip non-battery sources (UPS, etc.) when possible.
            if let type = description[kIOPSTypeKey as String] as? String,
               type != (kIOPSInternalBatteryType as String) {
                continue
            }
            let onBattery = (description[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSBatteryPowerValue as String)
            let capacity = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let percent = capacity > 0 ? (current * 100 / capacity) : 100
            return (onBattery, percent)
        }
        return (false, 100)
    }

    private func enterEcoMode() {
        brightnessBeforeEco = settings.brightness
        settings.ecoMode = true
        // Eco only dims; never raise a level that is already lower.
        settings.brightness = min(settings.brightness, 0.50)
    }

    private func exitEcoMode() {
        settings.ecoMode = false
        if let previous = brightnessBeforeEco {
            settings.brightness = previous
        }
        brightnessBeforeEco = nil
    }

    @objc func toggleEcoMode() {
        if !settings.ecoMode {
            enterEcoMode()
            userDisabledEco = false
            autoEnabledEco = false // user-initiated; don't auto-clear on AC/high battery
        } else {
            exitEcoMode()
            userDisabledEco = true
            autoEnabledEco = false
        }
        settings.saveManualEcoMode()
        menuBarManager.syncMenuStates()
        menuBarManager.updateStatusItem()
    }

    @objc func toggleAQI() {
        settings.showAQI.toggle()
        menuBarManager.syncDisplayModeSubmenu()
        menuBarManager.updateStatusItem()
    }

    // MARK: - Menu Selectors

    @objc func toggleAurora() {
        settings.showAurora.toggle()
        menuBarManager.syncMenuStates()
    }

    @objc func toggleWeatherAlerts() {
        settings.showWeatherAlerts.toggle()
        menuBarManager.syncMenuStates()
    }

    @objc func toggleBottomLine() {
        settings.showBottomLine.toggle()
        menuBarManager.syncMenuStates()
    }

    @objc func setWeatherUnit(_ sender: NSMenuItem) {
        if let unit = sender.representedObject as? OverlaySettings.WeatherUnit {
            settings.selectedUnit = unit
            menuBarManager.syncUnitSubmenu()
            menuBarManager.updateStatusItem()
        }
    }

    @objc func setDisplayMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? OverlaySettings.StatusBarDisplayMode {
            settings.displayMode = mode
            menuBarManager.syncDisplayModeSubmenu()
            menuBarManager.updateStatusItem()
        }
    }

    @objc func setBrightness(_ sender: NSMenuItem) {
        if let brightness = sender.representedObject as? Double {
            settings.brightness = brightness
            brightnessBeforeEco = nil // an explicit choice outlives Eco Mode
            menuBarManager.syncBrightnessSubmenu()
        }
    }

    @objc func setAuroraStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? OverlaySettings.AuroraStyle {
            settings.manualWeatherCode = style.weatherCode
            settings.manualIsNight = nightOverride(for: style)

            menuBarManager.syncAuroraStyleSubmenu()
        }
    }

    @objc func resetToDefaults() {
        settings.showAurora = true
        settings.showBottomLine = false
        settings.selectedUnit = .celsius
        settings.displayMode = .iconAndTemp
        settings.brightness = 1.0
        settings.manualWeatherCode = nil
        settings.manualIsNight = nil
        settings.ecoMode = false
        settings.showWeatherAlerts = true
        settings.showAQI = false
        settings.isPreviewing = false
        settings.previewWeatherCode = nil
        settings.previewIsNight = nil
        userDisabledEco = false
        autoEnabledEco = false
        brightnessBeforeEco = nil
        settings.saveManualEcoMode()

        menuBarManager.syncMenuStates()
        menuBarManager.updateStatusItem()
    }

    @objc func refreshWeather() {
        weatherManager.forceRefresh()
    }

    // MARK: - Multi-Location Management

    @objc func switchToSavedLocation(_ sender: NSMenuItem) {
        guard let saved = sender.representedObject as? SavedLocation else { return }
        weatherManager.switchToLocation(id: saved.id)
        menuBarManager.syncLocationsSubmenu()
    }

    @objc func switchToAutoLocation() {
        weatherManager.switchToAutoLocation()
        menuBarManager.syncLocationsSubmenu()
    }

    @objc func addLocation() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Location"
        alert.informativeText = "Enter a city name (e.g. \"Mumbai\", \"London\", \"New York\")."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "City name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let query = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let manager = weatherManager
        Task.detached {
            do {
                let match = try await manager.searchCity(query)
                DispatchQueue.main.async {
                    guard let self = AppDelegate.shared else { return }
                    if let match = match {
                        self.weatherManager.addSavedLocation(match)
                        self.menuBarManager.syncLocationsSubmenu()
                        self.menuBarManager.updateStatusItem()
                    } else {
                        self.showLocationAlert("No match", "No city found matching \"\(query)\". Try a different spelling.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    AppDelegate.shared?.showLocationAlert("Search failed", error.localizedDescription)
                }
            }
        }
    }

    @objc func removeLocation() {
        guard !weatherManager.savedLocations.isEmpty else {
            showLocationAlert("No Saved Locations", "You haven't added any locations yet.")
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Remove Location"
        alert.informativeText = "Select a location to remove:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        for saved in weatherManager.savedLocations {
            popup.addItem(withTitle: saved.name)
            popup.lastItem?.representedObject = saved
        }
        alert.accessoryView = popup
        alert.window.initialFirstResponder = popup

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        guard let selected = popup.selectedItem?.representedObject as? SavedLocation else { return }
        weatherManager.removeSavedLocation(id: selected.id)
        menuBarManager.syncLocationsSubmenu()
        menuBarManager.updateStatusItem()
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

    @objc func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Weather Overlay"
        alert.informativeText = "Version \(version)\n\nAmbient weather menu bar overlay for macOS."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func checkForUpdates() {
        updateManager.performUpdateCheck(isUserInitiated: true)
    }

    private func performUpdateCheck(isUserInitiated: Bool) {
        updateManager.performUpdateCheck(isUserInitiated: isUserInitiated)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSMenuDelegate
extension AppDelegate: NSMenuDelegate {
    public func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let item = item, let style = item.representedObject as? OverlaySettings.AuroraStyle else {
            clearPreviewState()
            return
        }

        settings.isPreviewing = true
        settings.previewWeatherCode = style.weatherCode
        settings.previewIsNight = nightOverride(for: style)
    }

    public func menuDidClose(_ menu: NSMenu) {
        clearPreviewState()
    }

    private func nightOverride(for style: OverlaySettings.AuroraStyle) -> Bool? {
        switch style {
        case .clearDay: return false
        case .clearNight: return true
        case .auto, .cloudy, .fog, .rain, .snow, .thunderstorm: return nil
        }
    }

    private func clearPreviewState() {
        settings.isPreviewing = false
        settings.previewWeatherCode = nil
        settings.previewIsNight = nil
    }
}
