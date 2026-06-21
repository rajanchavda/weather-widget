# Weather Menu Bar Overlay - AI Context

## Quick Project Summary
macOS menu bar weather app with real-time weather visualization using atmospheric aurora gradients, cinematic animated weather effects (rain with 3-layer depth + lightning, snow, twinkling stars), and optional temperature forecast line. Built with SwiftUI + Canvas GPU rendering, runs as a background accessory app.

## What This Project Does
1. Fetches weather data from Open-Meteo API using IP-based geolocation
2. Displays current temperature and weather emoji (☀️/🌙 day/night) in macOS menu bar
3. Overlays atmospheric gradient effects across the menu bar based on weather conditions
4. Renders cinematic animated weather effects (rain with depth + lightning, snow, stars)
5. Auto-refreshes weather every 5 minutes
6. Provides extensive menu controls for customization (brightness, aurora preview, units)

## Key Files Breakdown

### `main.swift` - Application Entry Point (389 lines)
**Purpose**: Main controller, runs the app and manages system integration

**Main Class**: `AppDelegate`
- Sets app to run as accessory (no Dock icon)
- Creates status bar item (shows weather emoji + temperature)
- Creates overlay window (transparent, spans menu bar)
- Builds dropdown menu with user controls
- Subscribes to weather updates using Combine
- Updates UI reactively when weather data changes

### `WeatherManager.swift` - Data Layer (195 lines)
**Purpose**: Handles all weather data fetching and state management

**Published Properties**:
```swift
@Published var currentTemp: Double
@Published var weatherCode: Int          // WMO code (0-99)
@Published var hourlyTemps: [Double]    // Next 12 hours
@Published var cityName: String
@Published var hasData: Bool
@Published var errorMessage: String?
```

**Network Flow**:
1. Try FreeIPAPI for geolocation → get lat/lon
2. If fails, try ipapi.co as fallback
3. Fetch weather from Open-Meteo using coordinates
4. If all fails, use London as default location
5. Auto-refresh every 5 minutes

### `OverlayView.swift` - Visual Layer (~378 lines)
**Purpose**: SwiftUI view hierarchy for all visual effects

**Components**:
1. `OverlaySettings` - User preferences (aurora, units, brightness, manual weather code override)
2. `OverlayView` - Main view combining visual layers
3. Aurora gradient - Weather-responsive colors
4. `RainView` - Cinematic 3-layer rain animation with GPU Canvas rendering
5. `SnowView` - Gentle snowfall animation
6. Stars view - High-density twinkling stars for clear nights
7. Temperature forecast line - Optional 12-hour graph

**View Hierarchy**:
```
ZStack:
  ├── Aurora Background (colored gradient based on weather)
  ├── Stars (clear night only, deterministic twinkling)
  ├── Weather Animations (rain/snow via TimelineView + Canvas)
  └── Temperature Forecast Line (optional graph)
```

**Rain Animation Technical Details**:
- **3-Layer Depth System**: Near (1.3x speed), Mid (1x speed), Far (0.7x speed)
- **Drop Count**: 15 (light), 25 (medium), 40 (heavy thunderstorm)
- **Physics**: 1.0px width, 8-14px variable length, depth-based opacity (0.5-0.8)
- **Wind Drift**: ±3px horizontal sway using sine wave
- **Color**: Blue-tinted water (RGB: 0.6, 0.75, 0.95) not white
- **Splashes**: Main splash + outer ripple rings on impact
- **Lightning**: Thunderstorm-only, 6-second interval, 0.15s flash duration, 25% opacity

## Weather Code System (WMO Standard)

| Code | Weather | Aurora Colors | Emoji | Animations |
|------|---------|---------------|-------|------------|
| 0-1 | Clear | Orange/Yellow (day)<br>Indigo/Purple (night) | ☀️/🌙 | Twinkling stars at night |
| 2-3 | Cloudy | Gray/Blue | ☁️ | - |
| 45-48 | Fog | White/Gray | 🌫️ | - |
| 51-67 | Rain/Drizzle | Blue/Purple | 🌧️ | Light rain (15 drops, 3-layer depth) |
| 71-77 | Snow | White/Cyan | ❄️ | Snow animation (25 flakes) |
| 80-82 | Showers | Blue/Purple | 🌦️ | Medium rain (25 drops, 3-layer depth) |
| 85-86 | Snow Showers | White/Cyan | 🌨️ | Snow animation (25 flakes) |
| 95-99 | Thunderstorm | Dark purple | ⛈️ | Heavy rain (40 drops) + lightning |

## Window Architecture

### Overlay Window Properties
**Key Challenge**: Create a window that:
- Sits on top of the menu bar
- Spans full width
- Lets clicks pass through to status items
- Doesn't appear in Dock or window switcher

**Solution**:
```swift
window.level = NSWindow.Level.statusBar.rawValue + 1  // Above menu bar
window.ignoresMouseEvents = true      // Click-through
window.backgroundColor = .clear       // Transparent
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

## State Management Pattern

### Architecture: Combine + SwiftUI
1. **WeatherManager** publishes changes via `@Published` properties
2. **AppDelegate** subscribes using Combine publishers
3. **OverlayView** observes via `@ObservedObject`

**Flow Example**:
```
Weather API → WeatherManager.currentTemp = 25.0
                     ↓ (@Published)
              AppDelegate receives update
                     ↓ (Combine sink)
              Updates status bar text
                     ↓
              OverlayView observes weatherManager
                     ↓ (@ObservedObject)
              SwiftUI re-renders with new colors
```

## User Customization Options

### Menu Bar Controls
1. **Atmospheric Aurora** - Master toggle for visual effects
2. **Bottom Forecast Line** - Shows 12-hour temperature graph (disabled by default)
3. **Temperature Unit** - Celsius (°C) or Fahrenheit (°F)
4. **Brightness** - 25%, 50%, 75%, 100%
5. **Try Different Aurora** - Preview all 8 aurora styles (Clear Day/Night, Cloudy, Fog, Rain, Snow, Thunderstorm) without waiting for real weather
6. **Reset to Defaults** - Restore all settings
7. **Force Refresh Weather** (⌘R) - Manual API fetch
8. **Quit Weather Overlay** (⌘Q)

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
- **Frameworks**: SwiftUI, Cocoa, Combine, Foundation
- **Dependencies**: None (pure Swift, no packages)

### Network APIs (All Free, No Auth)
1. **Open-Meteo** (weather data)
   - `https://api.open-meteo.com/v1/forecast`
   - No API key required
   
2. **FreeIPAPI** (geolocation, primary)
   - `https://freeipapi.com/api/json`
   
3. **ipapi.co** (geolocation, fallback)
   - `https://ipapi.co/json/`
   - Requires User-Agent header

### Build System
Swift Package Manager:
```swift
.platforms([.macOS(.v13)])
.executableTarget(name: "WeatherOverlay", path: "Sources")
```

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
- **Frequency**: Every 5 minutes (auto-refresh)
- **Timeout**: 5 seconds per request
- **Bandwidth**: <10 KB per weather fetch

### Rendering Optimization
- **GPU-accelerated**: Canvas rendering uses Metal (GPU), not CPU
- **Pure vector math**: No textures or image loading
- **Deterministic animations**: No random() calls per frame
- **Tiny render area**: Screen width × 24px height only

## Code Quality Notes

### Conventions Used
- **Naming**: Swift standard (camelCase, descriptive)
- **Comments**: Minimal, focused on "why" not "what"
- **Structure**: MARK comments divide logical sections
- **Error handling**: Do-try-catch with fallbacks
- **Async**: Modern Swift concurrency (async/await)

### Why Minimal Comments?
Well-named functions/variables are self-documenting. Comments only when non-obvious.

## File-by-File Summary

### `Package.swift` (18 lines)
- Swift Package Manager manifest
- Defines executable target
- macOS 13.0+ platform requirement

### `main.swift` (396 lines)
- `AppDelegate` class (app lifecycle)
- Status bar item management
- Menu creation and actions (aurora toggle, brightness, unit selection, aurora preview, reset)
- Overlay window setup
- Combine subscriptions
- Day/night detection for moon/sun emoji (6 PM - 6 AM)

### `WeatherManager.swift` (195 lines)
- Weather data fetching
- IP geolocation with fallback
- State management (`@Published`)
- 5-minute auto-refresh

### `OverlayView.swift` (378 lines)
- `OverlaySettings` class (preferences + manual weather override)
- `OverlayView` main view
- Aurora color mapping
- `RainView` struct (3-layer rain with lightning using TimelineView + Canvas)
- `SnowView` struct (snowfall animation)
- Stars generation (high-density twinkling)
- Temperature forecast graph

---

**Document Purpose**: Context for AI assistants to understand project structure and implementation.

**Last Updated**: 2026-06-21  
**Project Status**: Clean, functional  
**Complexity Level**: Beginner-Intermediate (SwiftUI + Combine + AppKit)
