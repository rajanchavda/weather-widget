# Weather Menu Bar Overlay - AI Context

## Quick Project Summary
macOS menu bar weather app with real-time weather visualization using atmospheric aurora gradients, cinematic animated weather effects (sun, clouds, fog, rain with 3-layer depth + lightning, snow, twinkling stars), and optional temperature forecast line. Built with SwiftUI + Canvas GPU rendering, runs as a background accessory app.

## What This Project Does
1. Fetches weather and air-quality data from Open-Meteo, for a saved city or, by default, a location found by IP-based geolocation
2. Displays current temperature and weather emoji (☀️/🌙 day/night) in macOS menu bar
3. Overlays atmospheric gradient effects across the menu bar based on weather conditions
4. Renders cinematic animated weather effects (sun, clouds, fog, rain with depth + lightning, snow, stars)
5. Auto-refreshes weather every 5 minutes
6. Sends notifications for weather approaching in the next two hours
7. Provides extensive menu controls for customization (locations, brightness, aurora preview, units, layout, Eco Mode)

## Key Files Breakdown

### `Sources/main.swift` - Bootstrap Entry Point (7 lines)
**Purpose**: Creates `AppDelegate` and runs the app

### `Sources/Core/App/AppDelegate.swift` - Application Controller (~673 lines)
**Purpose**: Main controller, runs the app and manages system integration

**Main Class**: `AppDelegate`
- Sets app to run as accessory (no Dock icon)
- Creates overlay windows (transparent, one per screen that has a menu bar)
- Hosts all `@objc` selectors for menu actions, including the Add/Remove Location dialogs
- Subscribes to WeatherManager + settings changes using `Publishers.Merge` with a 50 ms debounce (`observeChanges(_:)`)
- Manages login item registration
- Pauses on system sleep, display sleep and session switch (closes the windows); resumes on wake
- Battery monitor for Eco Mode (auto-on at ≤20% on battery)
- Delegates menu bar / status item to MenuBarManager
- Delegates update checks to UpdateManager
- Delegates weather alerts to NotificationManager

### `Sources/Core/App/MenuBarManager.swift` - Status Bar + Menu (~549 lines)
**Purpose**: Creates the NSStatusItem, builds full NSMenu, handles state sync with WeatherManager + OverlaySettings. Menu rows are found by `MenuTag` or by action selector, never by index.

### `Sources/Core/App/UpdateManager.swift` - Update Checker (~194 lines)
**Purpose**: Checks GitHub releases, runs Homebrew upgrade, relaunches app. The background check at launch only flags the update in the menu; `brew upgrade` runs only after the user confirms. The background check is skipped outside an `.app` bundle.

### `Sources/Core/Weather/WeatherManager.swift` - Data Layer (~604 lines)
**Purpose**: Handles all weather data fetching and state management

**Published Properties**:
```swift
@Published var currentTemp: Double
@Published var weatherCode: Int          // WMO code (0-99)
@Published var hourlyTemps: [Double]    // Next 12 hours
@Published var hourlyCodes: [Int]
@Published var hourlyTimes: [String]
@Published var hourlyPrecipitation: [Double]
@Published var cityName: String
@Published var isNight: Bool
@Published var isFetching: Bool
@Published var lastUpdated: Date?
@Published var hasData: Bool
@Published var errorMessage: String?
@Published var isPaused: Bool
@Published var isStale: Bool             // Last refresh failed, previous data still shown
@Published var aqiValue: Double?
@Published var aqiLabel: String
@Published var savedLocations: [SavedLocation]
@Published var activeLocationId: UUID?   // nil = Auto (IP-based)
```

**Derived**: `activeLocation: SavedLocation?` (the selected city, nil on Auto) and `currentPrecipitation: Double?`.

**Network Flow**:
1. If a saved city is active (`activeLocation`), use its coordinates; no IP lookup is made
2. Otherwise use the geo-IP result cached in memory, if it is under one hour old (`geoLocationCacheLifetime`) and not invalidated
3. Otherwise try FreeIPAPI for geolocation → get lat/lon; if that fails, try ipapi.co as fallback. If both fail, the previously held result is reused; with nothing held, the refresh fails
4. Fetch weather from Open-Meteo using coordinates, then air quality (an AQI failure is non-fatal)
5. On a failed refresh, keep the last good data marked stale (`isStale`) for up to 3 hours, same location only. Otherwise show an error. Another city is never substituted
6. Auto-refresh every 5 minutes

The geo-IP cache is invalidated by a network path change, by `resume()` and by `forceRefresh()` (Force Refresh Weather, ⌘R).

### `Sources/Core/Weather/Models.swift` - API Types (~114 lines)
**Purpose**: `SavedLocation` (Codable, persisted in UserDefaults), Codable response types (GeoResponse, FreeGeoResponse, GeocodingResponse, WeatherResponse, AirQualityResponse) and `AQICategory`

### `Sources/Core/Settings/OverlaySettings.swift` - User Preferences (~121 lines)
**Purpose**: ObservableObject with WeatherUnit, AuroraStyle, StatusBarDisplayMode enums, UserDefaults persistence (`WeatherOverlay.settings.<name>` keys)

### `Sources/Core/Views/OverlayView.swift` - Composition Root (~140 lines)
**Purpose**: ZStack dispatching to sub-views based on weather conditions; defines `OverlayAnimation.frameInterval` (30 fps cap)

### `Sources/Core/Utils/ColorHelpers.swift` - Color Functions (~53 lines)
**Purpose**: getTemperatureColor(), getAuroraColors() — centralized color logic

### `Sources/Core/Utils/Log.swift` - Logging (~17 lines)
**Purpose**: `enum Log` with one `os.Logger` per area (`Log.app`, `Log.weather`, `Log.update`, `Log.notifications`), subsystem `com.weatheroverlay.WeatherOverlay`

### `Sources/Core/Utils/NotificationManager.swift` - Weather Alerts (~198 lines)
**Purpose**: UserNotifications alerts on event onset (thunderstorm, rain, freezing rain, snow, fog, freezing temperature) within a 2-hour look-ahead, with a 3-hour cooldown

### Visual Sub-views (Sources/Core/Views/)
| File | Lines | Purpose |
|------|-------|---------|
| `AuroraBackground.swift` | 16 | Weather-responsive vertical gradient over the top half of the bar |
| `RainView.swift` | 213 | Cinematic 3-layer rain with Canvas GPU rendering, lightning; `RainIntensity` enum |
| `SnowView.swift` | 112 | Gentle snowfall animation via Canvas |
| `StarsView.swift` | 93 | High-density twinkling stars and a shooting star for clear nights |
| `SunView.swift` | 117 | Animated sun (rays, halo, lens flare) for clear day |
| `CloudView.swift` | 157 | Drifting clouds; amount and tint follow cloud cover and night |
| `FogView.swift` | 83 | Drifting blurred wisps for foggy weather |
| `TemperatureLineView.swift` | 41 | Optional 12-hour temperature forecast graph |

**View Hierarchy**:
```
ZStack:
  ├── Aurora Background (colored gradient based on weather)
  ├── Stars (clear night only, deterministic twinkling)
  ├── Sun / Clouds / Fog (clear day, cloudy, fog)
  ├── Weather Animations (rain/snow via TimelineView + Canvas)
  └── Temperature Forecast Line (optional graph)
```
Every animated view is driven by `TimelineView(.animation(minimumInterval: OverlayAnimation.frameInterval))` (30 fps). In Eco Mode it draws one frozen frame instead.

**Rain Animation Technical Details**:
- **3-Layer Depth System**: Near (1.3x speed), Mid (1x speed), Far (0.7x speed)
- **Drop Count**: 5 (drizzle), 10 (light), 25 (medium), 40 (heavy thunderstorm)
- **Fall time** (`baseSpeed`, seconds for the mid layer): 2.0 (drizzle), 0.9 (light), 0.7 (medium), 0.5 (heavy)
- **Physics**: 1.0px width × depth factor, variable length of about 4-14px (2-10px for drizzle), depth-based opacity (0.71-0.89)
- **Wind Drift**: ±3px horizontal sway using sine wave (±5px for drizzle); heavy rain also falls at a slant
- **Color**: Blue-tinted water (RGB: 0.6, 0.75, 0.95) not white
- **Splashes**: Ripple with an expanding ring and a rebounding droplet on impact; side splatter for near-layer drops
- **Lightning**: Thunderstorm-only, 6-second interval, 0.15s flash duration, 25% opacity
- **Precipitation gate**: every rain intensity, and with it the lightning, is drawn only when `weatherManager.currentPrecipitation > 0`, or during a hover preview in the aurora submenu (`OverlayView.shouldShowRainAnimation()`)

## Weather Code System (WMO Standard)

| Code | Weather | Aurora Colors | Emoji | Animations |
|------|---------|---------------|-------|------------|
| 0-1 | Clear | Orange/Yellow (day)<br>Indigo/Purple (night) | ☀️/🌙 | Animated sun by day, twinkling stars at night; code 1 adds 2 faint clouds |
| 2-3 | Cloudy | Gray/Blue | ☁️ | Code 2: sun or stars behind 3 clouds; code 3: 6 grayer clouds. Dim, cool clouds at night |
| 45, 48 | Fog | Warm White/Gray (day)<br>Dark Blue (night) | 🌫️ | Drifting fog wisps |
| 51-55 | Drizzle | Blue/Purple | 🌧️ | Drizzle (5 drops, slow, gated on precipitation) |
| 56-67 | Freezing Drizzle, Rain, Freezing Rain | Blue/Purple | 🌧️ | Light rain (10 drops, 3-layer depth, gated on precipitation) |
| 71-77 | Snow | White/Cyan | ❄️ | Snow animation (35 flakes) |
| 80-82 | Showers | Blue/Purple | 🌦️ | Medium rain (25 drops, 3-layer depth, gated on precipitation) |
| 85-86 | Snow Showers | White/Cyan | 🌨️ | Snow animation (35 flakes) |
| 95-99 | Thunderstorm | Dark purple | ⛈️ | Heavy rain (40 drops) + lightning, both gated on precipitation |
| Other | Unknown | Blue | 🌤️ | - |

## Window Architecture

### Overlay Window Properties
**Key Challenge**: Create a window that:
- Sits over the menu bar area, just below the status items
- Spans full width
- Lets clicks pass through to status items
- Doesn't appear in Dock or window switcher
- Does not float over other apps' fullscreen Spaces

**Solution** (`AppDelegate.makeOverlayWindow(frame:)`):
```swift
window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)  // One below status items
window.ignoresMouseEvents = true      // Click-through
window.backgroundColor = .clear       // Transparent
window.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
```

Joining all Spaces is deliberately avoided, and so is `.stationary`: both can leave the overlay visible over another app's fullscreen Space.

**Space switches**: on `NSWorkspace.activeSpaceDidChangeNotification`, `syncOverlayWindowsToActiveSpace()` brings each existing window forward and reuses it, with its view and running animation, if it is on the active Space. A window is rebuilt only if it did not follow. Screens without a menu bar (fullscreen) get no window. Screen configuration changes rebuild all windows after a 1.5 s delay.

## State Management Pattern

### Architecture: Combine + SwiftUI
1. **WeatherManager** + **OverlaySettings** publish changes via `objectWillChange`
2. **AppDelegate** subscribes using `Publishers.Merge(objectWillChange:)`, debounced by 50 ms
3. **OverlayView** observes via `@ObservedObject`

**Flow Example**:
```
Weather API → WeatherManager updates @Published property
                     ↓ (objectWillChange)
              AppDelegate receives update
                     ↓ (Publishers.Merge sink, 50 ms debounce)
              menuBarManager.updateStatusItem()
              menuBarManager.syncLocationsSubmenu()
              notificationManager.evaluateAndNotify()

              OverlayView observes weatherManager
                     ↓ (@ObservedObject)
              SwiftUI re-renders with new colors
```

## User Customization Options

### Menu Bar Controls
Built in `MenuBarManager.buildMenu(for:)`. Top level, in order:

1. **Location / Condition** - Two disabled info rows (city; temperature and description)
2. **Locations** (submenu) - Auto (IP-based), one item per saved city, Add Location..., Remove Location...
3. **Appearance** (submenu)
   - **Atmospheric Aurora** - Master toggle for the aurora and weather effects (the forecast line has its own toggle)
   - **Brightness** - 100%, 75%, 50%, 25%
   - **Try Different Aurora** - Preview the 7 aurora styles (Clear Day/Night, Cloudy, Fog, Rain, Snow, Thunderstorm) without waiting for real weather, or return to Auto. Hover previews, click selects
4. **Menu Bar Layout** (submenu)
   - Icon + Temperature, Icon Only, Temperature Only
   - **Show Air Quality Index** - Appends the European AQI to the status item (disabled by default)
   - **Bottom Forecast Line** - Shows 12-hour temperature graph (disabled by default)
5. **Settings** (submenu)
   - **Temperature Unit** - Celsius (°C) or Fahrenheit (°F)
   - **Weather Alerts** - Notification toggle (enabled by default)
   - **Eco Mode** - Freezes animations, caps brightness at 50%
   - **Launch at Login** - Registers through SMAppService
6. **Reset to Defaults** - Restore all settings (saved locations are kept)
7. **Force Refresh Weather** (⌘R) - Manual API fetch with a fresh location lookup
8. **Check for Updates** - GitHub release check; upgrade through Homebrew after confirmation
9. **About Weather Overlay** - Version info
10. **Quit Weather Overlay** (⌘Q)

## Temperature Forecast Graph (Optional Feature)

Displays 12-hour temperature forecast as a line graph at the bottom of the menu bar.

**Data Source**: `weatherManager.hourlyTemps` (array of 12 doubles)

**Rendering**:
- **Position**: Bottom 6px of menu bar (1-5px from bottom edge)
- **Style**: 2.5px stroke with rounded caps, gradient coloring
- **Y-axis**: Normalized to temperature range (min to max of 12 values)
- **X-axis**: Evenly distributed across screen width

**Color Gradient** (temperature-based):
- < 0°C: Deep Cyan
- 0-15°C: Cool Blue
- 15-22°C: Mild Green
- 22-30°C: Warm Gold
- > 30°C: Hot Red

## Technical Requirements

### System
- **macOS**: 13.0+ (Ventura or later)
- **Swift**: 5.9+
- **Frameworks**: SwiftUI, Cocoa, Combine, Foundation, Network, ServiceManagement, UserNotifications, IOKit, os
- **Dependencies**: None (pure Swift, no packages)

### Network APIs (All Free, No Auth)
1. **Open-Meteo** (weather data)
   - `https://api.open-meteo.com/v1/forecast`
   - No API key required

2. **Open-Meteo Air Quality** (European AQI)
   - `https://air-quality-api.open-meteo.com/v1/air-quality`

3. **Open-Meteo Geocoding** (city search for saved locations)
   - `https://geocoding-api.open-meteo.com/v1/search`
   
4. **FreeIPAPI** (geolocation, primary)
   - `https://freeipapi.com/api/json`
   
5. **ipapi.co** (geolocation, fallback)
   - `https://ipapi.co/json/`
   - Requires User-Agent header

6. **GitHub Releases** (update check)
   - `https://api.github.com/repos/rajanchavda/weather-widget/releases/latest`

### Build System
Swift Package Manager (3 targets):
- `WeatherOverlayCore` — Library target with all logic (supports `@testable import`)
- `WeatherOverlay` — Executable target (thin bootstrap entry point)
- `WeatherOverlayTests` — XCTest suite (270 tests)

```swift
.target(name: "WeatherOverlayCore", path: "Sources/Core")
.executableTarget(name: "WeatherOverlay", dependencies: ["WeatherOverlayCore"], path: "Sources", exclude: ["Core", "screenshots"])
.testTarget(name: "WeatherOverlayTests", dependencies: ["WeatherOverlayCore"])
```

### Packaging, Release and Signing
- `build_app.sh [version]` builds `WeatherOverlay.app`, signs it, archives it with `ditto` into `WeatherOverlay.zip`, verifies the unpacked archive, and reports `Signature:` and `Notarized:` lines plus the Homebrew cask
- `create_release.sh <version>` tags `v<version>` from a clean `main`; the tag starts `.github/workflows/release.yml` (tests, build, GitHub release, cask update in `rajanchavda/homebrew-tap`)
- `.github/workflows/tests.yml` runs `swift build` and `swift test` on pull requests and pushes to `main`
- **Current state**: no signing secrets are set, so releases are **ad-hoc signed and not notarized**, and the cask clears the quarantine attribute with `xattr -cr` after install
- **Present but inactive**: Developer ID signing (hardened runtime) and notarization, switched on by credentials. It has **not been exercised against Apple's notary service**
  - `build_app.sh` environment: `CODESIGN_IDENTITY`; `NOTARY_KEYCHAIN_PROFILE`, or `NOTARY_KEY_ID` + `NOTARY_KEY_PATH` (+ `NOTARY_ISSUER_ID`); `NOTARY_TIMEOUT`
  - `release.yml` secrets: `DEVELOPER_ID_CERTIFICATE_P12_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `CODESIGN_IDENTITY` (all three or none); `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, optional `NOTARY_ISSUER_ID` (needs the signing secrets). A partly configured set fails the release
- The cask template in `build_app.sh` and the one generated in `release.yml` must stay identical; both `zap` the preferences plist `~/Library/Preferences/com.weatheroverlay.WeatherOverlay.plist`

## Performance Characteristics

### Resource Usage
- **Memory**: ~57 MB (with animations), ~30-35 MB (idle)
- **CPU Usage**:
  - Idle (no animations): 0-0.5%
  - Light rain/snow: 1-3%
  - Thunderstorm (heavy rain + lightning): 3-5%
- **Battery Impact**: ~0.5-2% per hour (varies by weather)
  - Clear/Cloudy: 0.3-0.5% per hour
  - Rain/Snow: 0.8-1.2% per hour
  - Thunderstorm: 1.5-2% per hour

### Network
- **Frequency**: Every 5 minutes (auto-refresh): one forecast and one air-quality request; the geo-IP lookup at most once an hour, and only with Auto location
- **Timeout**: 15 seconds per request (30 seconds per resource)
- **Bandwidth**: <10 KB per weather fetch

### Rendering Optimization
- **GPU-accelerated**: Canvas rendering uses Metal (GPU), not CPU
- **Pure vector math**: No textures or image loading
- **Deterministic animations**: No random() calls per frame
- **Frame rate**: Capped at 30 fps (`OverlayAnimation.frameInterval`)
- **Tiny render area**: Screen width × menu bar height only
- **Window reuse**: Overlay windows are kept across Space switches instead of being rebuilt

## Development Workflow

### TDD Requirement
All new features must follow Test-Driven Development:
1. **Write the test first** — Define expected behavior in a failing XCTest case
2. **Implement the feature** — Write the minimal code to make the test pass
3. **Verify** — Run `swift test` and confirm all tests (new + existing) pass
4. **Refactor** — Clean up implementation while keeping tests green

Tests should cover: success paths, error/failure modes, boundary conditions, and any state mutations. Network-dependent code must use `URLProtocolMock` for deterministic mocking.

### Reading Logs
Diagnostics go to the macOS unified log through `Log` (`Sources/Core/Utils/Log.swift`), not to standard output: the app normally runs with no terminal attached.

```bash
# Live, including debug
log stream --level debug --predicate 'subsystem == "com.weatheroverlay.WeatherOverlay"'

# After the fact
log show --last 1h --info --predicate 'subsystem == "com.weatheroverlay.WeatherOverlay"'

# One area only: add a category (weather, app, update, notifications)
log stream --level debug --predicate 'subsystem == "com.weatheroverlay.WeatherOverlay" AND category == "weather"'
```

## Code Quality Notes

### Conventions Used
- **Naming**: Swift standard (camelCase, descriptive)
- **Comments**: Minimal, focused on "why" not "what"
- **Structure**: MARK comments divide logical sections
- **Error handling**: Do-try-catch with fallbacks
- **Async**: Modern Swift concurrency (async/await)
- **Logging**: `Log.<category>` (`os.Logger`) with an explicit `privacy:` on every interpolated value; coordinates and the city-search URL are `.private`

### Why Minimal Comments?
Well-named functions/variables are self-documenting. Comments only when non-obvious.

## File-by-File Summary

### `Package.swift` (~29 lines)
- Swift Package Manager manifest
- Defines 3 targets: `WeatherOverlayCore` (library), `WeatherOverlay` (executable), `WeatherOverlayTests` (tests)
- macOS 13.0+ platform requirement

### `Sources/main.swift` (7 lines)
- Bootstrap entry point
- Creates AppDelegate, NSApplication, runs app

### `Sources/Core/App/AppDelegate.swift` (~673 lines)
- App lifecycle + overlay window setup and reuse across Space switches
- @objc menu action routing, Add/Remove Location dialogs
- Publishers.Merge subscription (debounced) for reactive updates
- Login item registration
- Sleep/wake pause and resume, battery-aware Eco Mode
- NSMenuDelegate hover preview for aurora styles

### `Sources/Core/App/MenuBarManager.swift` (~549 lines)
- NSStatusItem creation
- Full NSMenu construction (Locations, Appearance, Menu Bar Layout, Settings submenus; reset, refresh, update, about, quit)
- State sync with WeatherManager + OverlaySettings
- `showUpdateAvailable(version:)`, `showUpdateInProgress()`

### `Sources/Core/App/UpdateManager.swift` (~194 lines)
- GitHub release checking
- Homebrew upgrade execution after user confirmation
- Relaunch after a successful upgrade

### `Sources/Core/Weather/WeatherManager.swift` (~604 lines)
- Weather and air-quality data fetching
- IP geolocation with fallback and a one-hour in-memory cache
- Saved locations (`savedLocations`, `activeLocationId`, derived `activeLocation`) and city search (`searchCities` returns up to five `CityMatch` values)
- One-time migration of the legacy `WeatherOverlay.manualLocation` UserDefaults key into a saved location; the key is then deleted
- State management (`@Published`)
- 5-minute auto-refresh, pause/resume, `forceRefresh()`
- Stale fetch guard (fetchGeneration); last good data kept as stale on failure

### `Sources/Core/Weather/Models.swift` (~114 lines)
- Codable API response types
- SavedLocation struct (the only location type)
- AQICategory enum

### `Sources/Core/Settings/OverlaySettings.swift` (~121 lines)
- User preferences (aurora toggle, forecast line, units, brightness, manual weather override, display mode, Eco Mode, weather alerts, AQI)
- UserDefaults persistence

### `Sources/Core/Views/OverlayView.swift` (~140 lines)
- ZStack composition root
- Dispatches to sub-views based on weather
- Precipitation gate for rain, Eco Mode freeze, 30 fps frame interval

### `Sources/Core/Utils/ColorHelpers.swift` (~53 lines)
- Aurora color mapping (getAuroraColors)
- Temperature color gradient (getTemperatureColor)

### `Sources/Core/Utils/Log.swift` (~17 lines)
- `os.Logger` instances per category (app, weather, update, notifications)

### `Sources/Core/Utils/NotificationManager.swift` (~198 lines)
- Weather alert classification and onset detection
- UserNotifications authorization and delivery

### Visual Sub-views
- `RainView.swift` (~213 lines) — 3-layer rain with lightning using TimelineView + Canvas
- `SnowView.swift` (~112 lines) — Snowfall animation
- `StarsView.swift` (~93 lines) — High-density twinkling stars
- `AuroraBackground.swift` (~16 lines) — Weather-responsive gradient
- `SunView.swift`, `CloudView.swift`, `FogView.swift` (~117, 157, 83 lines) — Animated sun, clouds and fog
- `TemperatureLineView.swift` (~41 lines) — Temperature forecast graph

### Test Suite (270 tests)
- **`AppDelegateTests.swift` (26)** — Aurora-style hover preview via NSMenuDelegate, Eco Mode toggle flags and brightness restore, nested menu checkmarks, change-sink debounce, overlay window reuse on Space sync, 30 fps cap, Eco Mode persistence rules, Reset to Defaults
- **`CloudCoverTests.swift` (4)** — `CloudView.CloudCover` code mapping, cloud count per level, overcast and night tints
- **`ColorHelpersTests.swift` (24)** — Temperature color boundaries, aurora colors for all WMO categories (day/night)
- **`MenuBarManagerTests.swift` (66)** — Status item text for all weather conditions, °C/°F formatting and rounding, error/no-data/update-ready states, display modes, location title including the stale note, `showUpdateInProgress()`, Eco Mode, AQI, About item, Locations submenu, layout checkmark sync
- **`ModelsTests.swift` (19)** — JSON decoding for WeatherResponse, GeoResponse, FreeGeoResponse, GeocodingResponse, AirQualityResponse; SavedLocation Codable round-trip, equality and persistence; AQICategory
- **`NotificationManagerTests.swift` (18)** — Alert classification per WMO code, precipitation gate, onset-only alerts, look-ahead window, cooldown, freezing temperature in the selected unit, suppression rules, city switch
- **`OverlaySettingsTests.swift` (32)** — Defaults, mutations, objectWillChange emission, WeatherUnit/AuroraStyle/StatusBarDisplayMode enum coverage, Eco Mode, AQI, UserDefaults persistence
- **`RainIntensityTests.swift` (4)** — Drop count, speed, height, wind sway and thunderstorm flag for drizzle, light, medium, heavy
- **`UpdateManagerTests.swift` (11)** — GitHub release JSON parsing, version comparison with `compare(_:options:.numeric)`, background check inside/outside an app bundle via URLProtocolMock, result handling
- **`WeatherManagerTests.swift` (66)** — Initial state, success fetch, stale-data fallback on failure, network error, saved location overrides geo, searchCities (top five, picker titles), night detection, stale response discard via fetchGeneration guard, saved locations, `activeLocation`, legacy migration, AQI fetch, precipitation, geo-IP cache
- **`Helpers/URLProtocolMock.swift`** — Custom URLProtocol subclass intercepting all URL requests; supports immediate and delayed responses for deterministic mock behavior

---

**Document Purpose**: Context for AI assistants to understand project structure and implementation.

**Last Updated**: 2026-10-19  
**Latest Release**: v2.4.1  
**Project Status**: Refactored into modular single-responsibility components  
**Complexity Level**: Beginner-Intermediate (SwiftUI + Combine + AppKit)
