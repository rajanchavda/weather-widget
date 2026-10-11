import os

/// Unified-logging loggers, one per area of the app.
///
/// Interpolated values are redacted unless annotated, so every call site states
/// `privacy:` explicitly: coordinates and search queries are `.private`, the rest `.public`.
enum Log {
    /// The bundle identifier, spelled out rather than read from `Bundle.main`: that is nil
    /// under `swift run` and the test runner's under XCTest, and one `log` predicate
    /// should match everywhere.
    static let subsystem = "com.weatheroverlay.WeatherOverlay"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let weather = Logger(subsystem: subsystem, category: "weather")
    static let update = Logger(subsystem: subsystem, category: "update")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
