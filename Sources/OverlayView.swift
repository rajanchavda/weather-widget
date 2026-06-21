import SwiftUI

// Display settings that will be controlled from the menu bar status item
class OverlaySettings: ObservableObject {
    @Published var showAurora: Bool = true
    @Published var showBottomLine: Bool = true
    @Published var selectedUnit: WeatherUnit = .celsius
    
    enum WeatherUnit: String, CaseIterable {
        case celsius = "°C"
        case fahrenheit = "°F"
    }
}

struct OverlayView: View {
    @ObservedObject var weatherManager: WeatherManager
    @ObservedObject var settings: OverlaySettings
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 1. Atmospheric Aurora Background
                if settings.showAurora {
                    auroraView
                        .transition(.opacity)
                }
                
                // 2. Sleek Bottom Temperature Forecast Line
                if settings.showBottomLine && weatherManager.hourlyTemps.count >= 12 {
                    temperatureLineView(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.easeInOut(duration: 0.8), value: weatherManager.weatherCode)
        .animation(.easeInOut(duration: 0.5), value: settings.showAurora)
        .animation(.easeInOut(duration: 0.5), value: settings.showBottomLine)
    }
    
    // MARK: - Aurora (Ambient background gradient)
    private var auroraView: some View {
        let colors = getAuroraColors()
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Temperature Forecast Line
    private func temperatureLineView(width: CGFloat, height: CGFloat) -> some View {
        let temps = weatherManager.hourlyTemps
        let minTemp = temps.min() ?? 0.0
        let maxTemp = temps.max() ?? 100.0
        let tempRange = max(maxTemp - minTemp, 1.0) // Avoid division by zero
        
        // Define color gradient representing the 12 forecast temperatures
        let lineGradient = LinearGradient(
            colors: temps.map { getTemperatureColor($0) },
            startPoint: .leading,
            endPoint: .trailing
        )
        
        return Path { path in
            let stepX = width / CGFloat(temps.count - 1)
            
            for i in 0..<temps.count {
                let x = CGFloat(i) * stepX
                
                // Normalize temp to a y-offset within the bottom 6px of the menu bar
                // High temp is at the top of our 6px drawing zone, low temp at the very bottom
                let normalizedTemp = (temps[i] - minTemp) / tempRange
                let yOffset = CGFloat(normalizedTemp) * 4.0 // Scale variation to 4px
                let y = height - 1.0 - yOffset // Draw in the bottom zone (1px to 5px from bottom)
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            lineGradient,
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Color Mapping Helpers
    
    private func getTemperatureColor(_ tempC: Double) -> Color {
        // We convert to Celsius internally for uniform mapping logic
        let temp = tempC
        if temp < 0 {
            return Color(red: 0.0, green: 0.8, blue: 1.0) // Deep Cyan (Freezing)
        } else if temp < 15 {
            return Color(red: 0.2, green: 0.6, blue: 0.9) // Cool Blue
        } else if temp < 22 {
            return Color(red: 0.3, green: 0.8, blue: 0.5) // Mild Green/Teal
        } else if temp < 30 {
            return Color(red: 0.95, green: 0.7, blue: 0.1) // Warm Gold/Yellow
        } else {
            return Color(red: 0.9, green: 0.2, blue: 0.1) // Hot Red/Orange
        }
    }
    
    private func getAuroraColors() -> [Color] {
        let code = weatherManager.weatherCode
        let isNight = checkIsNight()
        
        switch code {
        case 0, 1: // Clear
            if isNight {
                return [Color.indigo.opacity(0.12), Color.purple.opacity(0.08), Color.clear]
            } else {
                return [Color.orange.opacity(0.12), Color.yellow.opacity(0.08), Color.clear]
            }
        case 2, 3: // Cloudy
            return [Color.gray.opacity(0.15), Color.blue.opacity(0.08), Color.clear]
        case 45, 48: // Fog
            return [Color.white.opacity(0.15), Color.gray.opacity(0.08), Color.clear]
        case 51...67, 80...82: // Rain / Drizzle
            return [Color.blue.opacity(0.14), Color.purple.opacity(0.08), Color.clear]
        case 71...77, 85...86: // Snow
            return [Color.white.opacity(0.2), Color.cyan.opacity(0.08), Color.clear]
        case 95...99: // Thunderstorm
            return [Color(red: 0.1, green: 0.05, blue: 0.2).opacity(0.18), Color.purple.opacity(0.05), Color.clear]
        default:
            return [Color.blue.opacity(0.1), Color.clear]
        }
    }
    
    private func checkIsNight() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 6 || hour > 18
    }
}
