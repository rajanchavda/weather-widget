// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeatherOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WeatherOverlay", targets: ["WeatherOverlay"]),
        .library(name: "WeatherOverlayCore", targets: ["WeatherOverlayCore"])
    ],
    targets: [
        .target(
            name: "WeatherOverlayCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "WeatherOverlay",
            dependencies: ["WeatherOverlayCore"],
            path: "Sources",
            exclude: ["Core", "screenshots"]
        ),
        .testTarget(
            name: "WeatherOverlayTests",
            dependencies: ["WeatherOverlayCore"]
        )
    ]
)
