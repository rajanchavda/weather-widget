// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeatherOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WeatherOverlay", targets: ["WeatherOverlay"])
    ],
    targets: [
        .executableTarget(
            name: "WeatherOverlay",
            path: "Sources",
            exclude: ["screenshots"]
        )
    ]
)
