# Weather Menu Bar Overlay - Project Documentation

## Overview
A minimalist macOS menu bar weather application that displays real-time weather conditions with atmospheric aurora effects, cinematic animated weather (rain, snow, lightning), twinkling stars on clear nights, and an optional temperature forecast line.

## Architecture

### Core Components

#### 1. **AppDelegate** (`Sources/App/AppDelegate.swift`)
- Main application controller running as an accessory app (no Dock icon)
- Manages the overlay window (position, level, click-through)
- Delegates status bar / menu to `MenuBarManager` and updates to `UpdateManager`
- Handles login item registration, `@objc` menu action routing
- Reactive subscription to weather data changes via `Publishers.Merge(objectWillChange:)`

#### 1b. **MenuBarManager** (`Sources/App/MenuBarManager.swift`)
- Owns `NSStatusItem` and builds the full `NSMenu`
- Exposes `updateStatusItem()` (reads from WeatherManager directly) and `syncMenuStates()`, `syncUnitSubmenu()`
- All `@objc` selectors forward to AppDelegate

#### 1c. **UpdateManager** (`Sources/App/UpdateManager.swift`)
- Checks for new GitHub releases, runs Homebrew upgrade, relaunches the app
- Supports silent background updates and explicit "Check for Updates" menu item

#### 2. **WeatherManager** (`WeatherManager.swift`)
- Fetches weather data from Open-Meteo API
- Handles IP-based geolocation using FreeIPAPI with ipapi.co fallback
- Auto-refreshes every 5 minutes
- Publishes weather state via Combine `@Published` properties

**Published Properties:**
- `currentTemp`: Current temperature in Celsius
- `weatherCode`: WMO weather code (0-99)
- `hourlyTemps`: Next 12 hours temperature forecast
- `cityName`: Detected or fallback city name
- `hasData`, `isFetching`, `errorMessage`: State flags

**Error Handling:**
- Primary fetch with user's location
- Fallback to London (51.5074, -0.1278) on location failure
- Graceful error messages displayed in status bar

#### 3. **OverlayView** (`OverlayView.swift`)
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

#### 4. **OverlaySettings** (`Sources/Settings/OverlaySettings.swift`)
- `@ObservableObject` for user preferences
- Controls aurora visibility, forecast line, temperature units (°C/°F), brightness (25-100%), manual aurora style preview

## Weather Code Mapping (WMO Standard)

| Code Range | Weather Type | Visual Treatment |
|------------|-------------|------------------|
| 0-1 | Clear | Day: Orange/Yellow aurora, Sun emoji<br>Night: Indigo/Purple aurora, Moon emoji, Twinkling stars |
| 2-3 | Cloudy | Gray/Blue aurora, Cloud emoji |
| 45-48 | Fog | White/Gray aurora, Fog emoji |
| 51-67 | Rain/Drizzle | Blue/Purple aurora, Rain emoji, Light rain animation (15 drops, 3-layer depth) |
| 71-77 | Snow | White/Cyan aurora, Snowflake emoji, Snow animation (25 flakes) |
| 80-82 | Showers | Blue/Purple aurora, Shower emoji, Medium rain animation (25 drops, 3-layer depth) |
| 85-86 | Snow Showers | White/Cyan aurora, Snow emoji, Snow animation (25 flakes) |
| 95-99 | Thunderstorm | Dark purple aurora, Thunderstorm emoji, Heavy rain animation (40 drops, 3-layer depth) + Lightning flashes |

## Window Management

### Overlay Window Characteristics
- **Frame**: Spans entire menu bar width, positioned at top of main screen
- **Style**: Borderless, transparent background
- **Level**: `statusBar + 1` (renders above system menu bar blur)
- **Mouse Events**: Ignored (clicks pass through to status items)
- **Behavior**: Joins all spaces, fullscreen auxiliary mode
- **Updates**: Responds to screen configuration changes

### Frame Calculation
```swift
func getMenuBarFrame() -> NSRect {
    let screenFrame = NSScreen.main.frame
    let visibleFrame = NSScreen.main.visibleFrame
    let menuBarHeight = screenFrame.height - visibleFrame.maxY
    
    return NSRect(
        x: screenFrame.origin.x,
        y: screenFrame.origin.y + visibleFrame.maxY,
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
2. **Bottom Forecast Line** (Toggle) - Shows/hides temperature graph (disabled by default)
3. **Temperature Unit** (Submenu) - Celsius (°C) or Fahrenheit (°F)
4. **Brightness** (Submenu) - 25%, 50%, 75%, 100%
5. **Try Different Aurora** (Submenu) - Preview aurora styles without waiting for weather:
   - Auto (Weather-based) - Default
   - Clear Day, Clear Night, Cloudy, Foggy, Rainy, Snowy, Thunderstorm
6. **Reset to Defaults** - Restore all settings to original state
7. **Force Refresh Weather** (⌘R) - Manual weather data fetch
8. **Quit Weather Overlay** (⌘Q)

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
- Product: Executable (WeatherOverlay)
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

## Project Structure
```
WeatherOverlay/
├── Package.swift                 # Swift Package Manager manifest
├── README.md                     # Quick start guide
├── CLAUDE.md                     # This file - technical docs
├── GEMINI.md                     # AI context documentation
└── Sources/
    ├── main.swift                # Bootstrap entry point (6 lines)
    ├── App/
    │   ├── AppDelegate.swift     # App lifecycle, overlay window, @objc actions
    │   ├── MenuBarManager.swift  # Status item + NSMenu
    │   └── UpdateManager.swift   # GitHub release + Homebrew upgrade + relaunch
    ├── Weather/
    │   ├── WeatherManager.swift  # Weather fetching + state management
    │   └── Models.swift          # API response types, ManualLocation
    ├── Settings/
    │   └── OverlaySettings.swift # ObservableObject user preferences
    ├── Views/
    │   ├── OverlayView.swift     # ZStack composition root
    │   ├── AuroraBackground.swift
    │   ├── StarsView.swift
    │   ├── RainView.swift
    │   ├── SnowView.swift
    │   ├── SunView.swift
    │   ├── CloudView.swift
    │   ├── FogView.swift
    │   └── TemperatureLineView.swift
    └── Utils/
        └── ColorHelpers.swift    # Temperature + aurora color functions
```

---

**Last Updated**: 2026-06-28  
**Project Version**: 1.0  
**macOS Target**: 13.0+ (Ventura and later)
