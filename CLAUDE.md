# Weather Menu Bar Overlay - Project Documentation

## Overview
A minimalist macOS menu bar weather application that displays real-time weather conditions with atmospheric aurora effects, cinematic animated weather (sun, clouds, fog, rain, snow, lightning), twinkling stars on clear nights, and an optional temperature forecast line.

## Architecture

### Core Components

#### 1. **AppDelegate** (`Sources/Core/App/AppDelegate.swift`)
- `@MainActor` application controller running as an accessory app (no Dock icon)
- Manages overlay windows (one per screen that has a menu bar; position, level, click-through) — see Window Management
- Delegates status bar/menu to `MenuBarManager`, updates to `UpdateManager`, notifications to `NotificationManager`
- Handles login item registration (`SMAppService`), `@objc` menu action routing, and the Add/Remove Location dialogs (`addLocation()`, `removeLocation()`)
- `NSMenuDelegate` for the "Try Different Aurora" submenu: highlighting a style sets `settings.isPreviewing`, `previewWeatherCode`, `previewIsNight`; closing the menu clears them
- Reactive subscription to weather and settings changes via `observeChanges(_:)` (`Publishers.Merge` + 50 ms debounce, `AppDelegate.changeDebounce`)
- Power monitoring: battery check every 60 seconds. Eco Mode auto-enables on battery at ≤20% (unless the user turned it off) and auto-disables only if it was auto-enabled. Entering Eco Mode caps brightness at 50%; leaving it restores the previous level
- Pause/resume: system sleep, display sleep and session resign call `pauseAll()` (pauses `WeatherManager`, closes all overlay windows). System wake, display wake and session activation call `resumeAll()` (resumes `WeatherManager`, rebuilds the windows)
- Screen unlock (`com.apple.screenIsUnlocked`) triggers `fetchWeather()` and a delayed window rebuild

#### 1b. **MenuBarManager** (`Sources/Core/App/MenuBarManager.swift`)
- Creates the `NSStatusItem` (stored in `AppDelegate.statusItem`) and builds the full `NSMenu` in `buildMenu(for:)` — see User Controls for the structure
- Exposes `updateStatusItem()` (reads from WeatherManager directly), `syncMenuStates()`, `syncUnitSubmenu()`, `syncBrightnessSubmenu()`, `syncAuroraStyleSubmenu()`, `syncDisplayModeSubmenu()`, `syncLocationsSubmenu()`, `showUpdateAvailable(version:)`, `showUpdateInProgress()`
- Menu items target `AppDelegate`'s `@objc` methods
- Rows are found by `MenuTag` (`location`, `condition`, `locations`, `brightness`, `auroraStyle`, `layout`, `unit`) or by action selector, searching submenus recursively. Never look a row up by index
- Supports three status bar display modes: Icon+Temp, Icon Only, Temp Only
- Status item title: `💤` while paused, `⚠️ Err` on error, `🌤️ --` with no data, otherwise emoji and/or temperature (one decimal). Suffixes in order: ` AQI: <n> <label>` (when `showAQI` and a value exists), ` 🌱` (Eco Mode), ` ⚠️` (update available)
- Location row: `Location: <city>`, with ` (last updated <time>)` appended while the data is stale

#### 1c. **UpdateManager** (`Sources/Core/App/UpdateManager.swift`)
- Checks for new GitHub releases (`api.github.com/repos/rajanchavda/weather-widget/releases/latest`), runs Homebrew upgrade, relaunches the app
- Background check at launch only flags the update in the menu ("Update Available (vX)..."); `brew upgrade` runs only after the user confirms
- Background check is skipped outside an `.app` bundle (`swift run`)
- While upgrading, the status item reads "🌤️ Updating..." and the condition row is changed through `MenuBarManager.showUpdateInProgress()` (found by `MenuTag.condition`)
- The running version is `CFBundleShortVersionString` from the bundle's `Info.plist`, which `build_app.sh` writes; there is no version constant in the source

#### 1d. **NotificationManager** (`Sources/Core/Utils/NotificationManager.swift`)
- `@MainActor` class managing `UserNotifications` for weather alerts
- Requests `.alert` + `.sound` authorization on launch
- Evaluates hourly forecast for: thunderstorms (95-99), freezing rain (56-57, 66-67), rain (61-65, 80-82, only above 1.0 mm), snow (71-77, 85-86), fog (45-48), freezing temperatures (≤ 0°C). Drizzle (51-55) never alerts
- Notifies on event onset only: one alert when an event first enters the 2-hour look-ahead, none while it is ongoing, re-armed once it has passed (3-hour cooldown damps flickering forecasts)
- No alerts while the data is stale; alert state resets when the city changes
- Notification subtitle carries the city; freezing alerts use the selected temperature unit
- Formats time strings to `h:mm a` display, includes "in about X minutes" logic

#### 1e. **Log** (`Sources/Core/Utils/Log.swift`)
- `enum Log` with one `os.Logger` per area: `Log.app`, `Log.weather`, `Log.update`, `Log.notifications`
- Subsystem is the constant `com.weatheroverlay.WeatherOverlay` (`Log.subsystem`), spelled out rather than read from `Bundle.main` so one `log` predicate matches under `swift run`, XCTest and the app bundle
- Every interpolated value states `privacy:` explicitly: coordinates and the city-search URL are `.private`, everything else `.public`
- See Logging below for the levels in use and the commands to read the log

#### 2. **WeatherManager** (`Sources/Core/Weather/WeatherManager.swift`)
- Fetches weather data from Open-Meteo API (weather + air quality)
- Handles IP-based geolocation using FreeIPAPI with ipapi.co fallback, cached in memory for one hour
- Auto-refreshes every 5 minutes (300s) via Combine `Timer.publish`
- Publishes weather state via Combine `@Published` properties
- NWPathMonitor integration for instant re-fetch on network reconnect
- Multi-city support via `SavedLocation` persistence in UserDefaults
- `searchCity()` async method using Open-Meteo Geocoding API, returns `SavedLocation?` (first match only)
- Pause/resume lifecycle (`pause()`, `resume()`) for system sleep, display sleep and session switches
- `forceRefresh()` for the Force Refresh Weather menu item: invalidates the geo-IP cache, then fetches
- Air quality fetch from `air-quality-api.open-meteo.com` (European AQI), after every successful weather fetch

**Published Properties:**
- `currentTemp`: Current temperature in Celsius
- `weatherCode`: WMO weather code (0-99)
- `hourlyTemps`: Next 12 hours temperature forecast, starting at the location's current hour
- `hourlyCodes`: Next 12 hours WMO codes
- `hourlyTimes`: Next 12 hours ISO timestamps
- `hourlyPrecipitation`: Next 12 hours precipitation (mm)
- `cityName`: Detected or saved city name
- `isNight`: Night detection from API `is_day` field; local fallback (before 06:00 or from 20:00) only when a fetch fails with no usable data
- `hasData`, `isFetching`, `errorMessage`: State flags
- `lastUpdated`: Time of the last successful fetch
- `isPaused`: Paused state (display sleep, etc.)
- `isStale`: Last refresh failed and the previous good data is still shown
- `aqiValue`: European AQI value (optional)
- `aqiLabel`: Human-readable AQI category label
- `savedLocations`: Array of `SavedLocation` for multi-city support
- `activeLocationId`: Currently selected location UUID (nil = auto IP-based)

**Derived (not `@Published`):**
- `activeLocation`: The selected `SavedLocation`, or nil when the location is automatic. The only source of the selected city
- `currentPrecipitation`: Current hour precipitation, nil when there is no hourly data

**Error Handling:**
- Primary fetch with user's location
- On a failed refresh, the last good data stays on screen marked stale (`isStale`), for up to 3 hours (`maxStaleAge`) and only for the same location
- With no usable data, an error is shown; another city is never substituted
- Stale response discard via generation counter (`fetchGeneration`)
- Non-fatal AQI errors (weather data still valid)
- Graceful error messages displayed in status bar

**Multi-Location Support:**
- `SavedLocation` struct with UUID, name, lat/lon, persisted via UserDefaults (`WeatherOverlay.savedLocations`); the active id is stored under `WeatherOverlay.activeLocationId`
- `savedLocations` + `activeLocationId` are the single source of truth; there is no separate "manual location" type or property
- One-time legacy migration (`migrateLegacyManualLocation()`): a city stored under the old `WeatherOverlay.manualLocation` key becomes the active saved location when no saved locations exist; the key is then deleted in every case
- `switchToLocation(id:)`, `switchToAutoLocation()`, `addSavedLocation(_:)` (ignores duplicates, makes the new city active), `removeSavedLocation(id:)` (removing the active city returns to auto); each one persists and fetches
- Locations submenu: Auto (IP-based) + saved locations + Add/Remove dialogs
- City search via Open-Meteo Geocoding API with admin1/country display name

**Geo-IP Cache (Auto location only):**
- The last successful IP lookup is kept in memory for one hour (`WeatherManager.geoLocationCacheLifetime`) instead of being queried on every 5-minute refresh. Nothing is written to disk, so a relaunch always looks up afresh
- Looked up again after a network path change (`networkPathDidUpdate(connectionRestored:)`), after `resume()`, and on `forceRefresh()`. These call `invalidateGeoLocationCache()`, which marks the entry for revalidation but keeps it as a fallback
- If both providers fail, the held result is still used, even when expired; with nothing held the refresh fails
- A superseded fetch never writes the cache
- Saved cities never read or write the cache
- The clock is injectable (`now`) so tests can age an entry without sleeping

#### 3. **OverlayView** (`Sources/Core/Views/OverlayView.swift`)
- SwiftUI view hierarchy for menu bar visuals
- Visual layers, bottom to top (everything except the forecast line is inside `if settings.showAurora`):
  1. **Aurora Background**: Weather-responsive vertical gradient over the top half of the bar (`AuroraBackground`)
  2. **Stars**: Clear night only (`StarsView`)
  3. **Sky Effects**: Sun for clear day (`SunView`), clouds (`CloudView`), fog (`FogView`)
  4. **Precipitation**: Rain with lightning for thunderstorms (`RainView`), snow (`SnowView`)
  5. **Temperature Forecast Line**: 12-hour graph (optional, `TemperatureLineView`)
- Effective weather code and night flag: hover preview (`settings.isPreviewing`) wins, then the selected aurora style (`settings.manualWeatherCode`, `manualIsNight`), then `WeatherManager`
- Eco Mode passes a fixed `freezeDate` to every animated view, which then draws a single static frame
- `OverlayAnimation.frameInterval` (1/30 s) is defined here

**Rain Animation System** (`Sources/Core/Views/RainView.swift`, `RainView.RainIntensity`):

| Intensity | WMO codes | Drops | `baseSpeed` (s per fall, mid layer) | `baseHeight` | `windSway` |
|-----------|-----------|-------|-------------------------------------|--------------|------------|
| `.drizzle` | 51-55 | 5 | 2.0 | 3.0 | ±5px |
| `.light` | 56-67 | 10 | 0.9 | 6.0 | ±3px |
| `.medium` | 80-82 | 25 | 0.7 | 6.0 | ±3px |
| `.heavy` | 95-99 | 40 | 0.5 | 6.0 | ±3px |

- **Precipitation gate**: every intensity is drawn only when `shouldShowRainAnimation()` is true, i.e. `weatherManager.currentPrecipitation > 0`, or always during a hover preview (`settings.isPreviewing`). A selected (clicked) aurora style does not bypass the gate
- **3-Layer Depth**: Near (depth factor 1.3), Mid (1.0), Far (0.7), about a third of the drops each. Fall time is `baseSpeed / depthFactor`, so near drops fall faster
- **Physics**: Drop width 1px × depth factor; length (`baseHeight` + 0 to 5) × depth factor, about 4-14px (2-10px for drizzle); depth-based opacity (0.71-0.89)
- **Wind Effect**: Continuous horizontal drift of ±`windSway` using a sine wave; `.heavy` also falls at a slant
- **Water Color**: Blue-tinted (RGB: 0.6, 0.75, 0.95) for realism
- **Splashes**: Ripple ellipse with an expanding ring and a rebounding droplet; side splatter particles for near-layer drops
- **Lightning**: `.heavy` only (`isThunderstorm`). Full-screen white flash (25% opacity, 0.15s duration, every 6 seconds). It is drawn inside `RainView`, so it is behind the same precipitation gate

**Snow Animation** (`SnowView.swift`, codes 71-77 and 85-86, not gated on precipitation):
- 35 snowflakes in three depth layers with sine-wave flutter, wind drift and variable speeds, plus a 3px frost gradient along the bottom edge

**Stars Animation** (`StarsView.swift`, codes 0-1 at night):
- High-density stars (1 per 25px width) with deterministic twinkling (about 3.4-12.6s cycles), and a shooting star every 15 seconds

**Sun, Clouds, Fog** (Canvas animations, not emoji):
- `SunView.swift` (codes 0-1 by day): 12 rotating rays, pulsing halo, drifting lens flare, 15 dust motes
- `CloudView.swift` (codes 2-3): 6 clouds drifting at different speeds and sizes
- `FogView.swift` (codes 45, 48): 8 blurred wisps over the top half of the bar; lighter tint by day, cooler by night

#### 4. **OverlaySettings** (`Sources/Core/Settings/OverlaySettings.swift`)
- `ObservableObject` for user preferences
- Controls aurora visibility, forecast line, temperature units (°C/°F), brightness (25-100%), selected aurora style (`manualWeatherCode`, `manualIsNight`), status bar display mode, Eco Mode, weather alerts, AQI display
- Persisted in `UserDefaults` under `WeatherOverlay.settings.<name>` (`OverlaySettings.Key`). `AppDelegate` uses `OverlaySettings(defaults: .standard)`; `OverlaySettings()` is in-memory and writes nothing (used by tests)
- `ecoMode` is stored only through `saveManualEcoMode()`, so battery-triggered Eco Mode does not outlive the session; brightness is not stored while Eco Mode is dimming it
- Hover preview state (`isPreviewing`, `previewWeatherCode`, `previewIsNight`) is never stored

## Weather Code Mapping (WMO Standard)

| Code Range | Weather Type | Visual Treatment |
|------------|-------------|------------------|
| 0-1 | Clear | Day: Orange/Yellow aurora, Sun emoji, animated sun<br>Night: Indigo/Purple aurora, Moon emoji, Twinkling stars |
| 2-3 | Cloudy | Gray/Blue aurora, Cloud emoji, drifting clouds |
| 45, 48 | Fog | Day: warm White/Gray aurora; Night: dark Blue aurora; Fog emoji, drifting fog wisps |
| 51-55 | Drizzle | Blue/Purple aurora, Rain emoji, Drizzle animation (5 drops, slow, gated on precipitation) |
| 56-67 | Freezing Drizzle, Rain, Freezing Rain | Blue/Purple aurora, Rain emoji, Light rain animation (10 drops, 3-layer depth, gated on precipitation) |
| 71-77 | Snow | White/Cyan aurora, Snowflake emoji, Snow animation (35 flakes) |
| 80-82 | Showers | Blue/Purple aurora, Shower emoji, Medium rain animation (25 drops, 3-layer depth, gated on precipitation) |
| 85-86 | Snow Showers | White/Cyan aurora, Snow emoji, Snow animation (35 flakes) |
| 95-99 | Thunderstorm | Dark purple aurora, Thunderstorm emoji, Heavy rain animation (40 drops, 3-layer depth) + Lightning flashes, both gated on precipitation |
| Other | Unknown | Blue aurora, 🌤️ emoji, no animation |

Sources of truth: `getAuroraColors()` in `Sources/Core/Utils/ColorHelpers.swift` (aurora), `getWeatherEmoji()` and `getWeatherDescription()` in `MenuBarManager.swift` (emoji and condition text), `OverlayView.swift` (which view is shown).

## Window Management

### Overlay Window Characteristics
- **Count**: One window per screen whose menu bar frame is taller than 1pt (a screen showing a fullscreen app has no menu bar and gets no window)
- **Frame**: Spans entire menu bar width, positioned at top of each screen
- **Style**: Borderless, transparent background, no shadow, `isReleasedWhenClosed = false`
- **Level**: `statusBar - 1` (one below the status-bar level, so status items draw above the overlay)
- **Mouse Events**: Ignored (clicks pass through to status items)
- **Behavior**: `collectionBehavior = [.moveToActiveSpace, .ignoresCycle]`. Joining all Spaces is deliberately avoided so the overlay does not float over other apps' fullscreen Spaces, and `.stationary` is not used either
- **Space switches** (`activeSpaceDidChange` → `syncOverlayWindowsToActiveSpace()`): each existing window is brought forward with `orderFrontRegardless()` and kept, with its view and running animation, if it is then on the active Space. A window is closed and rebuilt only if it did not follow; windows with no matching screen are closed. Skipped while paused. If no window results, a full rebuild is retried after 1.5 s
- **Screen changes**: `didChangeScreenParametersNotification` rebuilds all windows (`setupOverlayWindows()`) after a 1.5 s delay (multi-monitor)
- **Sleep**: all windows are closed on pause and rebuilt on resume

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
- **Shown when**: `settings.showBottomLine` is on and at least 12 hourly values exist; independent of the aurora toggle
- **Position**: Bottom 6px of menu bar
- **Style**: Gradient stroke (2.5px width) with rounded caps
- **Color Mapping**: Temperature-based gradient
  - < 0°C: Deep Cyan (freezing)
  - 0-15°C: Cool Blue
  - 15-22°C: Mild Green/Teal
  - 22-30°C: Warm Gold/Yellow
  - > 30°C: Hot Red/Orange

## User Controls (Menu Bar)

### Menu Structure
Built in `MenuBarManager.buildMenu(for:)`. Top level, in order:

1. **Location: …** (disabled info row, `MenuTag.location`)
2. **Condition: …** (disabled info row, `MenuTag.condition`) - temperature and description; reads "Status: Downloading update via Homebrew..." during an upgrade
3. **Locations** (Submenu, `MenuTag.locations`, rebuilt by `syncLocationsSubmenu()`)
   - Auto (IP-based)
   - One item per saved location (the active one is checked)
   - Add Location... - city search dialog
   - Remove Location... - picker dialog
4. **Appearance** (Submenu)
   - **Atmospheric Aurora** (Toggle) - Enables/disables the aurora and all weather effects (not the forecast line)
   - **Brightness** (Submenu, `MenuTag.brightness`) - 100%, 75%, 50%, 25%
   - **Try Different Aurora** (Submenu, `MenuTag.auroraStyle`) - Hover previews a style, click selects it:
     - Auto (Weather-based) - Default
     - Clear Day, Clear Night, Cloudy, Foggy, Rainy, Snowy, Thunderstorm
5. **Menu Bar Layout** (Submenu, `MenuTag.layout`)
   - Display modes: Icon + Temperature, Icon Only, Temperature Only
   - **Show Air Quality Index** (Toggle, off by default)
   - **Bottom Forecast Line** (Toggle) - Shows/hides temperature graph (disabled by default)
6. **Settings** (Submenu)
   - **Temperature Unit** (Submenu, `MenuTag.unit`) - Use °C, Use °F
   - **Weather Alerts** (Toggle) - Enables/disables weather notification alerts
   - **Eco Mode** (Toggle) - Battery-aware auto-toggle at ≤20%, particle freeze, brightness reduction
   - **Launch at Login** (Toggle) - Register via SMAppService
7. **Reset to Defaults** - Restore all settings to original state (saved locations and Launch at Login are untouched)
8. **Force Refresh Weather** (⌘R) - `WeatherManager.forceRefresh()`
9. **Check for Updates** - GitHub release check + Homebrew upgrade; title becomes "Update Available (vX)..." once a newer release is found
10. **About Weather Overlay** - Version info
11. **Quit Weather Overlay** (⌘Q)

Separators follow items 3, 6 and 7. Locations are managed only through the Locations submenu; there is no separate top-level item for choosing or clearing a city.

## Technical Details

### Dependencies
- **Platform**: macOS 13.0+ (Ventura)
- **Frameworks**: SwiftUI, Cocoa, Combine, Foundation, Network, ServiceManagement, UserNotifications, IOKit, os
- **APIs**: 
  - Open-Meteo forecast (weather data, no API key required)
  - Open-Meteo air quality (European AQI)
  - Open-Meteo geocoding (city search)
  - FreeIPAPI (geolocation, primary)
  - ipapi.co (geolocation, fallback)
  - GitHub releases API (update check)

### Build Configuration
- Swift Tools Version: 5.9
- Products: Executable (WeatherOverlay), Library (WeatherOverlayCore)
- Targets: WeatherOverlayCore (library), WeatherOverlay (executable), WeatherOverlayTests (tests)
- No external package dependencies
- `build_app.sh [version]` packages `WeatherOverlay.app` and `WeatherOverlay.zip`; `create_release.sh <version>` tags a release from `main` (see Release and Signing)
- CI: `.github/workflows/tests.yml` runs `swift build` and `swift test` on pull requests and pushes to `main`

### Performance Considerations
- **Network**: 15-second request timeout (30 seconds per resource)
- **Update Frequency**: 5-minute auto-refresh cycle
- **Requests per refresh**: forecast + air quality; the geo-IP lookup at most once an hour (Auto location only)
- **Memory**: ~57 MB (with animations running), ~30-35 MB (idle)
- **CPU Usage**: 
  - Idle (no animations): 0-0.5%
  - Light rain/snow: 1-3%
  - Thunderstorm (heavy rain + lightning): 3-5%
- **Battery Impact**: ~0.5-2% per hour depending on weather conditions
- **Rendering**: GPU-accelerated Canvas (Metal), pure vector math, no textures
- **Frame rate**: All effects are capped at 30 fps (`OverlayAnimation.frameInterval`)
- **Space switches**: Existing overlay windows are moved to the active Space and reused; a window is rebuilt only if it did not follow

## State Management

### Reactive Architecture
- **Pattern**: Combine publishers + SwiftUI `@ObservedObject`
- **Flow**: WeatherManager + OverlaySettings → AppDelegate (status item, Locations submenu, alerts). OverlayView observes WeatherManager and OverlaySettings directly
- **Thread Safety**: All UI updates dispatched to main thread

### Publisher Chain
```swift
Publishers.Merge(
    weatherManager.objectWillChange.map { _ in () },
    settings.objectWillChange.map { _ in () }
)
.debounce(for: .milliseconds(50), scheduler: RunLoop.main)
.sink { /* update status item, sync locations submenu, evaluate alerts */ }
```

The debounce coalesces the burst of changes from one fetch into a single refresh. Menu actions still update the status item directly, so clicks are not delayed.

## Logging

All diagnostics go to the macOS unified log through `Log` (`Sources/Core/Utils/Log.swift`). The app is started by Homebrew or at login with no terminal attached, so nothing is written to standard output.

- **Subsystem**: `com.weatheroverlay.WeatherOverlay`
- **Categories**: `app` (lifecycle, windows, Eco Mode, login item), `weather` (fetching, location, cache), `update`, `notifications`
- **Levels**: `debug` for step-by-step fetch tracing, `info` for normal lifecycle and results, `notice` for things worth finding later (network restored, stale data kept, Eco Mode auto-enabled, login item changes, legacy migration), `error` for failures
- **Privacy**: state `privacy:` on every interpolation. Coordinates and the city-search URL are `.private`; the rest is `.public`

```bash
# Live, including debug
log stream --level debug --predicate 'subsystem == "com.weatheroverlay.WeatherOverlay"'

# After the fact
log show --last 1h --info --predicate 'subsystem == "com.weatheroverlay.WeatherOverlay"'

# One area only: add a category (weather, app, update, notifications)
log stream --level debug --predicate 'subsystem == "com.weatheroverlay.WeatherOverlay" AND category == "weather"'
```

## Release and Signing

- **Flow**: `./create_release.sh <version>` (on a clean `main`) pushes tag `v<version>` → `.github/workflows/release.yml` runs `swift test`, runs `build_app.sh`, creates the GitHub release with `WeatherOverlay.zip`, and regenerates `Casks/weatheroverlay.rb` in `rajanchavda/homebrew-tap`
- **Current state**: no signing secrets are set (the owner has no Apple Developer account). Releases are **ad-hoc signed and not notarized**, and the cask strips the quarantine attribute with `xattr -cr` in a `postflight`
- **Present but inactive**: Developer ID signing (hardened runtime, secure timestamp) and notarization in `build_app.sh` and `release.yml`. This path has **not been exercised against Apple's notary service**
- **`build_app.sh` environment**: `CODESIGN_IDENTITY`; either `NOTARY_KEYCHAIN_PROFILE` or `NOTARY_KEY_ID` + `NOTARY_KEY_PATH` (+ `NOTARY_ISSUER_ID` for a team key); `NOTARY_TIMEOUT` (default `30m`). Notary credentials without `CODESIGN_IDENTITY` fail before the build
- **`release.yml` secrets**: signing is `DEVELOPER_ID_CERTIFICATE_P12_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `CODESIGN_IDENTITY` (all three or none); notarization is `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, optional `NOTARY_ISSUER_ID`, and needs the signing secrets. A partly configured set fails the release. `HOMEBREW_TAP_TOKEN` is already in use
- **Local signed build**: `CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_KEYCHAIN_PROFILE="<profile>" ./build_app.sh <version>`
- **Archive**: made with `ditto -c -k --keepParent --norsrc`; the script unpacks it and verifies the signature (and the stapled ticket when notarized), then reports `Signature:` and `Notarized:` lines, the SHA-256 and the cask
- **Cask**: the template at the end of `build_app.sh` and the one generated in `release.yml` must stay identical. Both have `zap trash: "~/Library/Preferences/com.weatheroverlay.WeatherOverlay.plist"`; the `xattr -cr` postflight is omitted only for a notarized build

## Code Conventions

- **Naming**: Descriptive Swift conventions (camelCase)
- **Comments**: Minimal, focused on "why" not "what"
- **Structure**: MARK comments separate logical sections
- **State**: Prefer `@Published` (Combine) over manual notifications
- **Animations**: Declarative SwiftUI modifiers
- **Async**: Swift concurrency (`async`/`await`) for network calls
- **Logging**: Use `Log.<category>` with an explicit `privacy:` on every interpolated value; do not write diagnostics to standard output

## Testing

### Test Suite
- **Framework**: XCTest via Swift Package Manager (`swift test`)
- **Total Tests**: 262
- **Coverage**: Not measured (no coverage tooling in the repo). Tests exist for WeatherManager, MenuBarManager, UpdateManager, NotificationManager, OverlaySettings, Models, ColorHelpers, and parts of AppDelegate. The SwiftUI views are not rendered in tests; only `RainView.RainIntensity` and the frame-rate constant are checked

### Test Files
| File | Tests | What It Covers |
|------|-------|----------------|
| `AppDelegateTests.swift` | 26 | Aurora-style hover preview through `NSMenuDelegate`, Eco Mode toggle flags and brightness save/restore, nested menu checkmarks, change-sink debounce (`observeChanges`), overlay window reuse/creation/cleanup on Space sync, 30 fps cap, persistence of manual vs. automatic Eco Mode, Reset to Defaults |
| `ColorHelpersTests.swift` | 24 | Temperature color boundaries, aurora colors (all WMO categories, day/night) |
| `MenuBarManagerTests.swift` | 66 | Status item text (all emoji types), °C/°F formatting and rounding, error/no-data states, update-ready indicator, display modes, location row including the stale "last updated" note, `showUpdateInProgress()`, Eco Mode leaf and menu item, AQI display and toggle item, About item, Locations submenu, aurora submenu delegate, layout checkmark sync |
| `ModelsTests.swift` | 19 | JSON decoding for all API types (incl. AQI, Geocoding), SavedLocation Codable round-trip, equality and persistence, AQICategory |
| `NotificationManagerTests.swift` | 18 | Alert classification per WMO code (freezing rain before rain, precipitation gate), onset-only alerts, look-ahead window, cooldown, freezing temperature in the selected unit, suppression (stale data, alerts off, no data), city switch |
| `OverlaySettingsTests.swift` | 32 | Defaults, mutations, objectWillChange emission, enum coverage, display mode, eco mode, AQI toggle, UserDefaults persistence (round trip, invalid values, Eco Mode rules, in-memory mode) |
| `RainIntensityTests.swift` | 4 | `dropCount`, `baseSpeed`, `baseHeight`, `windSway`, `isThunderstorm` for drizzle, light, medium, heavy |
| `UpdateManagerTests.swift` | 11 | GitHub release JSON parsing, version comparison, background check inside/outside an app bundle and on network error, result handling (flag the menu without installing) |
| `WeatherManagerTests.swift` | 62 | Initial state, success fetch, failed refresh keeps last good data as stale (age limit, location switch, recovery), network error, saved location overrides geo, searchCity, night detection, stale response discard, saved locations (add/switch/remove/persist), `activeLocation`, legacy manual-location migration, AQI fetch, precipitation, geo-IP cache (lifetime, invalidation, fallback, resume, races) |

### Test Helpers
- **URLProtocolMock** — Custom URLProtocol subclass that intercepts all URL requests for deterministic mocking without modifying production code; supports per-URL delayed responses

### Running Tests
```bash
swift test
# Run a single suite:
swift test --filter WeatherManagerTests
```

## Project Structure
```
WeatherOverlay/
├── Package.swift                 # Swift Package Manager manifest (3 targets)
├── README.md                     # Quick start guide
├── CLAUDE.md                     # This file - technical docs
├── GEMINI.md                     # AI context documentation
├── build_app.sh                  # Build, sign, notarize (optional), zip, emit cask
├── create_release.sh             # Tag a release from main
├── AppIcon.icns                  # App icon
├── .github/
│   └── workflows/
│       ├── tests.yml             # swift build + swift test on PRs and main
│       └── release.yml           # Tag-triggered release + Homebrew cask
├── Sources/
│   ├── main.swift                # Bootstrap entry point (7 lines)
│   ├── screenshots/              # README images
│   └── Core/
│       ├── App/
│       │   ├── AppDelegate.swift # App lifecycle, overlay windows, @objc actions
│       │   ├── MenuBarManager.swift # Status item + NSMenu
│       │   └── UpdateManager.swift  # GitHub release + Homebrew upgrade + relaunch
│       ├── Weather/
│       │   ├── WeatherManager.swift # Weather fetching + state management
│       │   └── Models.swift         # API response types, SavedLocation, AQICategory
│       ├── Settings/
│       │   └── OverlaySettings.swift # ObservableObject user preferences
│       ├── Views/
│       │   ├── OverlayView.swift     # ZStack composition root
│       │   ├── AuroraBackground.swift
│       │   ├── StarsView.swift
│       │   ├── RainView.swift
│       │   ├── SnowView.swift
│       │   ├── SunView.swift
│       │   ├── CloudView.swift
│       │   ├── FogView.swift
│       │   └── TemperatureLineView.swift
│       └── Utils/
│           ├── ColorHelpers.swift # Temperature + aurora color functions
│           ├── Log.swift          # os.Logger instances (unified logging)
│           └── NotificationManager.swift # Weather alert notifications
└── Tests/
    └── WeatherOverlayTests/
        ├── AppDelegateTests.swift
        ├── ColorHelpersTests.swift
        ├── MenuBarManagerTests.swift
        ├── ModelsTests.swift
        ├── NotificationManagerTests.swift
        ├── OverlaySettingsTests.swift
        ├── RainIntensityTests.swift
        ├── UpdateManagerTests.swift
        ├── WeatherManagerTests.swift
        └── Helpers/
            └── URLProtocolMock.swift
```

---

**Last Updated**: 2026-10-11  
**Project Version**: 2.3.1 (latest release tag `v2.3.1`)  

