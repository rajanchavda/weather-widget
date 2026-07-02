# Weather Menu Bar Overlay - Project Documentation

## Overview
A minimalist macOS menu bar weather application that displays real-time weather conditions with atmospheric aurora effects, cinematic animated weather (rain, snow, lightning), twinkling stars on clear nights, and an optional temperature forecast line.

## Architecture

### Core Components

#### 1. **AppDelegate** (`Sources/Core/App/AppDelegate.swift`)
- Main application controller running as an accessory app (no Dock icon)
- Manages overlay windows (one per screen, position, level, click-through)
- Delegates status bar/menu to `MenuBarManager`, updates to `UpdateManager`, notifications to `NotificationManager`
- Handles login item registration (`SMAppService`), `@objc` menu action routing
- Reactive subscription to weather data changes via `Publishers.Merge(objectWillChange:)`
- Power monitoring: battery-aware Eco Mode auto-toggle at ≤20% battery
- Display sleep/screen lock/session switch detection: pauses WeatherManager + closes overlay windows
- Network path monitoring for reconnect-triggered instant fetch

#### 1b. **MenuBarManager** (`Sources/Core/App/MenuBarManager.swift`)
- Owns `NSStatusItem` and builds the full `NSMenu`
- Exposes `updateStatusItem()` (reads from WeatherManager directly) and `syncMenuStates()`, `syncUnitSubmenu()`, `syncDisplayModeSubmenu()`, `syncLocationsSubmenu()`
- All `@objc` selectors forward to AppDelegate
- Supports three status bar display modes: Icon+Temp, Icon Only, Temp Only

#### 1c. **UpdateManager** (`Sources/Core/App/UpdateManager.swift`)
- Checks for new GitHub releases, runs Homebrew upgrade, relaunches the app
- Supports silent background updates and explicit "Check for Updates" menu item

#### 1d. **NotificationManager** (`Sources/Core/Utils/NotificationManager.swift`)
- `@MainActor` class managing `UserNotifications` for weather alerts
- Requests `.alert` + `.sound` authorization on launch
- Evaluates hourly forecast for: thunderstorms, rain (with precipitation gate), freezing rain, snow, fog, freezing temperatures
- Uses `alertedEvents` dedup set to avoid repeat notifications
- Formats time strings to `h:mm a` display, includes "X minutes away" logic

#### 2. **WeatherManager** (`Sources/Core/Weather/WeatherManager.swift`)
- Fetches weather data from Open-Meteo API (weather + air quality)
- Handles IP-based geolocation using FreeIPAPI with ipapi.co fallback
- Auto-refreshes every 5 minutes (300s) via Combine `Timer.publish`
- Publishes weather state via Combine `@Published` properties
- NWPathMonitor integration for instant re-fetch on network reconnect
- Multi-city support via `SavedLocation` persistence in UserDefaults
- `searchCity()` async method using Open-Meteo Geocoding API
- Pause/resume lifecycle for display sleep/screen lock
- Air quality fetch from `air-quality-api.open-meteo.com` (European AQI)

**Published Properties:**
- `currentTemp`: Current temperature in Celsius
- `weatherCode`: WMO weather code (0-99)
- `hourlyTemps`: Next 12 hours temperature forecast
- `hourlyCodes`: Next 12 hours WMO codes
- `hourlyTimes`: Next 12 hours ISO timestamps
- `hourlyPrecipitation`: Next 12 hours precipitation (mm)
- `currentPrecipitation`: Computed current hour precipitation
- `cityName`: Detected or fallback city name
- `isNight`: Night detection from API `is_day` field or local fallback
- `hasData`, `isFetching`, `errorMessage`: State flags
- `isPaused`: Paused state (display sleep, etc.)
- `aqiValue`: European AQI value (optional)
- `aqiLabel`: Human-readable AQI category label
- `savedLocations`: Array of `SavedLocation` for multi-city support
- `activeLocationId`: Currently selected location UUID (nil = auto IP-based)

**Error Handling:**
- Primary fetch with user's location
- Fallback to London (51.5074, -0.1278) on location failure
- Stale response discard via generation counter
- Non-fatal AQI errors (weather data still valid)
- Graceful error messages displayed in status bar

**Multi-Location Support:**
- `SavedLocation` struct with UUID, name, lat/lon, persisted via UserDefaults
- Legacy `ManualLocation` migration to SavedLocation
- Locations submenu: Auto (IP-based) + saved locations + Add/Remove dialogs
- City search via Open-Meteo Geocoding API with admin1/country display name

#### 3. **OverlayView** (`Sources/Core/Views/OverlayView.swift`)
- SwiftUI view hierarchy for menu bar visuals
- Four main visual layers:
  1. **Aurora Background**: Weather-responsive gradient
  2. **Animated Weather Effects**: Rain (3-layer depth with lightning for thunderstorms), snow, stars
  3. **Temperature Forecast Line**: 12-hour graph (optional)
  
**Rain Animation System:**
- **3-Layer Depth**: Near (30%), Mid (30%), Far (40%) with parallax speed
- **Physics**: Variable drop length (8-14px), depth-based opacity (0.5-0.8)
- **Wind Effect**: Continuous ±3px horizontal drift using sine wave
- **Water Color**: Blue-tinted (RGB: 0.6, 0.75, 0.95) for realism
- **Splashes**: Main splash + outer ripple rings
- **Lightning**: Full-screen white flash (25% opacity, 0.15s duration, every 6 seconds)

**Snow Animation:**
- 25 snowflakes with sine-wave drift and variable speeds

**Stars Animation:**
- High-density stars (1 per 25px width) with deterministic twinkling (1.2-4.7s cycles)

#### 4. **OverlaySettings** (`Sources/Core/Settings/OverlaySettings.swift`)
- `@ObservableObject` for user preferences
- Controls aurora visibility, forecast line, temperature units (°C/°F), brightness (25-100%), manual aurora style preview

## Weather Code Mapping (WMO Standard)

| Code Range | Weather Type | Visual Treatment |
|------------|-------------|------------------|
| 0-1 | Clear | Day: Orange/Yellow aurora, Sun emoji<br>Night: Indigo/Purple aurora, Moon emoji, Twinkling stars |
| 2-3 | Cloudy | Gray/Blue aurora, Cloud emoji |
| 45-48 | Fog | White/Gray aurora, Fog emoji |
| 51-55 | Drizzle | Blue/Purple aurora, Rain emoji, No rain animation (excluded, gate on precipitation) |
| 61-67 | Rain | Blue/Purple aurora, Rain emoji, Light rain animation (15 drops, 3-layer depth, gated on precipitation) |
| 71-77 | Snow | White/Cyan aurora, Snowflake emoji, Snow animation (25 flakes) |
| 80-82 | Showers | Blue/Purple aurora, Shower emoji, Medium rain animation (25 drops, 3-layer depth) |
| 85-86 | Snow Showers | White/Cyan aurora, Snow emoji, Snow animation (25 flakes) |
| 95-99 | Thunderstorm | Dark purple aurora, Thunderstorm emoji, Heavy rain animation (40 drops, 3-layer depth) + Lightning flashes |

## Window Management

### Overlay Window Characteristics
- **Frame**: Spans entire menu bar width, positioned at top of each screen
- **Style**: Borderless, transparent background
- **Level**: `statusBar - 1` (renders below system menu bar but above other content)
- **Mouse Events**: Ignored (clicks pass through to status items)
- **Behavior**: Joins all spaces, fullscreen auxiliary mode
- **Updates**: Responds to screen configuration changes (multi-monitor)

### Frame Calculation
```swift
func getMenuBarFrame(for screen: NSScreen) -> NSRect {
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
```

## Temperature Forecast Visualization

### Graph Implementation (Optional Feature)
- **Data Source**: `weatherManager.hourlyTemps` (12 values)
- **Position**: Bottom 6px of menu bar
- **Style**: Gradient stroke (2.5px width) with rounded caps
- **Color Mapping**: Temperature-based gradient
  - < 0°C: Deep Cyan (freezing)
  - 0-15°C: Cool Blue
  - 15-22°C: Mild Green/Teal
  - 22-30°C: Warm Gold/Yellow
  - > 30°C: Hot Red/Orange

## User Controls (Menu Bar)

### Configuration Options
1. **Atmospheric Aurora** (Toggle) - Enables/disables all visual effects
2. **Weather Alerts** (Toggle) - Enables/disables weather notification alerts
3. **Bottom Forecast Line** (Toggle) - Shows/hides temperature graph (disabled by default)
4. **Temperature Unit** (Submenu) - Celsius (°C) or Fahrenheit (°F)
5. **Status Bar Display** (Submenu) - Display modes: Icon+Temp, Icon Only, Temp Only; plus Show Air Quality Index toggle
6. **Brightness** (Submenu) - 25%, 50%, 75%, 100%
7. **Eco Mode** (Toggle) - Battery-aware auto-toggle at ≤20%, particle freeze, brightness reduction
8. **Try Different Aurora** (Submenu) - Preview aurora styles without waiting for weather:
   - Auto (Weather-based) - Default
   - Clear Day, Clear Night, Cloudy, Foggy, Rainy, Snowy, Thunderstorm
9. **Locations** (Submenu) - Auto (IP-based), saved locations, Add/Remove dialogs
10. **Launch at Login** (Toggle) - Register via SMAppService
11. **Reset to Defaults** - Restore all settings to original state
12. **Force Refresh Weather** (⌘R) - Manual weather data fetch
13. **Check for Updates** - GitHub release check + Homebrew upgrade
14. **About Weather Overlay** - Version info
15. **Quit Weather Overlay** (⌘Q)

## Technical Details

### Dependencies
- **Platform**: macOS 13.0+ (Ventura)
- **Frameworks**: SwiftUI, Cocoa, Combine, Foundation
- **APIs**: 
  - Open-Meteo (weather data, no API key required)
  - FreeIPAPI (geolocation, primary)
  - ipapi.co (geolocation, fallback)

### Build Configuration
- Swift Tools Version: 5.9
- Products: Executable (WeatherOverlay), Library (WeatherOverlayCore)
- Targets: WeatherOverlayCore (library), WeatherOverlay (executable), WeatherOverlayTests (tests)
- No external package dependencies

### Performance Considerations
- **Network**: 5-second timeout for all HTTP requests
- **Update Frequency**: 5-minute auto-refresh cycle
- **Memory**: ~57 MB (with animations running), ~30-35 MB (idle)
- **CPU Usage**: 
  - Idle (no animations): 0-0.5%
  - Light rain/snow: 1-3%
  - Thunderstorm (heavy rain + lightning): 3-5%
- **Battery Impact**: ~0.5-2% per hour depending on weather conditions
- **Rendering**: GPU-accelerated Canvas (Metal), pure vector math, no textures

## State Management

### Reactive Architecture
- **Pattern**: Combine publishers + SwiftUI `@ObservedObject`
- **Flow**: WeatherManager → AppDelegate → OverlayView
- **Thread Safety**: All UI updates dispatched to main thread

### Publisher Chain
```swift
Publishers.Merge(
    weatherManager.objectWillChange.map { _ in () },
    settings.objectWillChange.map { _ in () }
)
.receive(on: RunLoop.main)
.sink { [weak self] in self?.menuBarManager.updateStatusItem() }
```

## Code Conventions

- **Naming**: Descriptive Swift conventions (camelCase)
- **Comments**: Minimal, focused on "why" not "what"
- **Structure**: MARK comments separate logical sections
- **State**: Prefer `@Published` (Combine) over manual notifications
- **Animations**: Declarative SwiftUI modifiers
- **Async**: Swift concurrency (`async`/`await`) for network calls

## Testing

### Test Suite
- **Framework**: XCTest via Swift Package Manager (`swift test`)
- **Total Tests**: 168
- **Coverage**: 100% of logic/state layers (WeatherManager, MenuBarManager, UpdateManager, OverlaySettings, Models, ColorHelpers)

### Test Files
| File | Tests | What It Covers |
|------|-------|----------------|
| `ColorHelpersTests.swift` | 24 | Temperature color boundaries, aurora colors (all WMO categories, day/night) |
| `ModelsTests.swift` | 22 | JSON decoding for all API types (incl. AQI, Geocoding), ManualLocation + SavedLocation Codable round-trip, AQICategory |
| `OverlaySettingsTests.swift` | 23 | Defaults, mutations, objectWillChange emission, enum coverage, display mode, eco mode, AQI toggle |
| `WeatherManagerTests.swift` | 29 | Initial state, success fetch, geo-failure fallback, network error, manual location, searchCity, night detection, stale response discard, saved locations, AQI fetch, precipitation, pause/resume |
| `MenuBarManagerTests.swift` | 61 | Status item text (all emoji types), °C/°F formatting, error/no-data states, update-ready indicator, AQI display, eco mode, display modes, locations submenu, paused state |
| `UpdateManagerTests.swift` | 9 | GitHub release JSON parsing, version comparison, network integration with mock |

### Test Helpers
- **URLProtocolMock** — Custom URLProtocol subclass that intercepts all URL requests for deterministic mocking without modifying production code

### Running Tests
```bash
swift test
# For verbose output:
swift test --filter WeatherManagerTests
```

## Project Structure
```
WeatherOverlay/
├── Package.swift                 # Swift Package Manager manifest (3 targets)
├── README.md                     # Quick start guide
├── CLAUDE.md                     # This file - technical docs
├── GEMINI.md                     # AI context documentation
├── Sources/
│   ├── main.swift                # Bootstrap entry point (6 lines)
│   ├── Core/
│   │   ├── App/
│   │   │   ├── AppDelegate.swift # App lifecycle, overlay window, @objc actions
│   │   │   ├── MenuBarManager.swift # Status item + NSMenu
│   │   │   └── UpdateManager.swift  # GitHub release + Homebrew upgrade + relaunch
│   │   ├── Weather/
│   │   │   ├── WeatherManager.swift # Weather fetching + state management
│   │   │   └── Models.swift         # API response types, ManualLocation
│   │   ├── Settings/
│   │   │   └── OverlaySettings.swift # ObservableObject user preferences
│   │   ├── Views/
│   │   │   ├── OverlayView.swift     # ZStack composition root
│   │   │   ├── AuroraBackground.swift
│   │   │   ├── StarsView.swift
│   │   │   ├── RainView.swift
│   │   │   ├── SnowView.swift
│   │   │   ├── SunView.swift
│   │   │   ├── CloudView.swift
│   │   │   ├── FogView.swift
│   │   │   └── TemperatureLineView.swift
│   │   └── Utils/
│   │       ├── ColorHelpers.swift # Temperature + aurora color functions
│   │       └── NotificationManager.swift # Weather alert notifications
└── Tests/
    └── WeatherOverlayTests/
        ├── ColorHelpersTests.swift
        ├── ModelsTests.swift
        ├── OverlaySettingsTests.swift
        ├── WeatherManagerTests.swift
        ├── MenuBarManagerTests.swift
        ├── UpdateManagerTests.swift
        └── Helpers/
            └── URLProtocolMock.swift
```

---

**Last Updated**: 2026-07-03  
**Project Version**: 1.0  

