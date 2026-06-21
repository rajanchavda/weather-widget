import Cocoa
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    
    var overlayWindow: NSWindow?
    var statusItem: NSStatusItem?
    let weatherManager = WeatherManager()
    let settings = OverlaySettings()
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching started.")
        // Run as an accessory app (background agent) so there's no Dock icon or main menu
        NSApp.setActivationPolicy(.accessory)
        
        print("[AppDelegate] Setting up status item and overlay window...")
        setupStatusItem()
        setupOverlayWindow()
        
        // Listen for system resolution changes or screen configuration updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Observe WeatherManager publishers and update the status item UI reactively
        print("[AppDelegate] Subscribing to WeatherManager publishers...")
        Publishers.CombineLatest(
            Publishers.CombineLatest3(weatherManager.$currentTemp, weatherManager.$weatherCode, weatherManager.$cityName),
            Publishers.CombineLatest(weatherManager.$hasData, weatherManager.$errorMessage)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] info, status in
            let (temp, code, city) = info
            let (hasData, errMsg) = status
            print("[AppDelegate] Publisher event received: temp=\(temp)°C, code=\(code), city=\(city), hasData=\(hasData), error=\(errMsg ?? "nil")")
            self?.updateStatusItem(temp: temp, code: code, city: city, hasData: hasData, error: errMsg)
        }
        .store(in: &cancellables)
        
        print("[AppDelegate] Starting the Weather Engine...")
        // Start the weather engine once AppKit is fully launched
        weatherManager.start()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "🌤️ --"
        }
        
        let menu = NSMenu()
        
        // Header / Status info
        let titleItem = NSMenuItem(title: "Weather Menu Bar Overlay", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let locationItem = NSMenuItem(title: "Location: Detecting...", action: nil, keyEquivalent: "")
        locationItem.isEnabled = false
        menu.addItem(locationItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Configuration: Aurora Toggle
        let auroraToggle = NSMenuItem(title: "Atmospheric Aurora", action: #selector(toggleAurora), keyEquivalent: "")
        auroraToggle.target = self
        auroraToggle.state = settings.showAurora ? .on : .off
        menu.addItem(auroraToggle)
        
        // Configuration: Bottom line graph toggle
        let lineToggle = NSMenuItem(title: "Bottom Forecast Line", action: #selector(toggleBottomLine), keyEquivalent: "")
        lineToggle.target = self
        lineToggle.state = settings.showBottomLine ? .on : .off
        menu.addItem(lineToggle)
        
        // Submenu: Temperature Unit selector
        let unitMenu = NSMenu()
        for unit in OverlaySettings.WeatherUnit.allCases {
            let item = NSMenuItem(title: "Use \(unit.rawValue)", action: #selector(setWeatherUnit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = unit
            item.state = settings.selectedUnit == unit ? .on : .off
            unitMenu.addItem(item)
        }
        
        let unitItem = NSMenuItem(title: "Temperature Unit", action: nil, keyEquivalent: "")
        unitItem.submenu = unitMenu
        menu.addItem(unitItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Commands
        let refreshItem = NSMenuItem(title: "Force Refresh Weather", action: #selector(refreshWeather), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let quitItem = NSMenuItem(title: "Quit Weather Overlay", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func setupOverlayWindow() {
        let frame = getMenuBarFrame()
        
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        // Core visual properties: float in status bar + make clicks pass through
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Embed the SwiftUI view hierarchy inside the AppKit window
        let hostingView = NSHostingView(rootView: OverlayView(weatherManager: weatherManager, settings: settings))
        window.contentView = hostingView
        
        // Display the window
        window.makeKeyAndOrderFront(nil)
        self.overlayWindow = window
    }
    
    @objc private func screenParametersChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.overlayWindow else { return }
            let frame = self.getMenuBarFrame()
            window.setFrame(frame, display: true)
        }
    }
    
    private func getMenuBarFrame() -> NSRect {
        guard let mainScreen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 1920, height: 24)
        }
        
        let screenFrame = mainScreen.frame
        let visibleFrame = mainScreen.visibleFrame
        
        // Menu bar height calculation: Difference between full screen height and top bounds of visible content area
        let menuBarHeight = screenFrame.height - visibleFrame.maxY
        
        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y + visibleFrame.maxY,
            width: screenFrame.width,
            height: menuBarHeight
        )
    }
    
    private func updateStatusItem(temp: Double, code: Int, city: String, hasData: Bool, error: String?) {
        guard let button = statusItem?.button else { return }
        
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
            title = String(format: "%@ %.1f%@", emoji, displayedTemp, settings.selectedUnit.rawValue)
            locationTitle = "Location: \(city)"
        }
        
        button.title = title
        
        // Dynamic location/error label update in menu items
        if let menu = statusItem?.menu, menu.items.count > 1 {
            menu.items[1].title = locationTitle
        }
    }
    
    private func getWeatherEmoji(_ code: Int) -> String {
        switch code {
        case 0, 1: return "☀️"
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
    
    // MARK: - Menu Selectors
    
    @objc private func toggleAurora() {
        settings.showAurora.toggle()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(toggleAurora) }) {
            item.state = settings.showAurora ? .on : .off
        }
    }
    
    @objc private func toggleBottomLine() {
        settings.showBottomLine.toggle()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(toggleBottomLine) }) {
            item.state = settings.showBottomLine ? .on : .off
        }
    }
    
    @objc private func setWeatherUnit(_ sender: NSMenuItem) {
        if let unit = sender.representedObject as? OverlaySettings.WeatherUnit {
            settings.selectedUnit = unit
            
            if let submenu = sender.menu {
                for item in submenu.items {
                    item.state = (item.representedObject as? OverlaySettings.WeatherUnit) == unit ? .on : .off
                }
            }
            
            updateStatusItem(temp: weatherManager.currentTemp, code: weatherManager.weatherCode, city: weatherManager.cityName, hasData: weatherManager.hasData, error: weatherManager.errorMessage)
        }
    }
    
    @objc private func refreshWeather() {
        weatherManager.fetchWeather()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// App Bootstrap
let delegate = await MainActor.run { AppDelegate() }
let app = NSApplication.shared
app.delegate = delegate
app.run()
