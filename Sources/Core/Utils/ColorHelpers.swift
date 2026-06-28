import SwiftUI

func getTemperatureColor(_ tempC: Double) -> Color {
    let temp = tempC
    if temp < 0 {
        return Color(red: 0.0, green: 0.8, blue: 1.0)
    } else if temp < 15 {
        return Color(red: 0.2, green: 0.6, blue: 0.9)
    } else if temp < 22 {
        return Color(red: 0.3, green: 0.8, blue: 0.5)
    } else if temp < 30 {
        return Color(red: 0.95, green: 0.7, blue: 0.1)
    } else {
        return Color(red: 0.9, green: 0.2, blue: 0.1)
    }
}

func getAuroraColors(weatherCode: Int, isNight: Bool) -> [Color] {
    switch weatherCode {
    case 0, 1:
        if isNight {
            return [Color.indigo.opacity(0.12), Color.purple.opacity(0.08), Color.clear]
        } else {
            return [Color.orange.opacity(0.12), Color.yellow.opacity(0.08), Color.clear]
        }
    case 2, 3:
        return [Color.gray.opacity(0.22), Color(white: 0.7).opacity(0.15), Color.blue.opacity(0.08), Color.clear]
    case 45, 48:
        if isNight {
            return [
                Color(red: 0.10, green: 0.13, blue: 0.25).opacity(0.25),
                Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.18),
                Color(red: 0.28, green: 0.35, blue: 0.48).opacity(0.12),
                Color.clear
            ]
        } else {
            return [
                Color(red: 0.85, green: 0.83, blue: 0.80).opacity(0.30),
                Color(red: 0.95, green: 0.90, blue: 0.82).opacity(0.22),
                Color(red: 0.90, green: 0.90, blue: 0.92).opacity(0.15),
                Color.clear
            ]
        }
    case 51...67, 80...82:
        return [Color.blue.opacity(0.14), Color.purple.opacity(0.08), Color.clear]
    case 71...77, 85...86:
        return [Color.white.opacity(0.2), Color.cyan.opacity(0.08), Color.clear]
    case 95...99:
        return [Color(red: 0.1, green: 0.05, blue: 0.2).opacity(0.18), Color.purple.opacity(0.05), Color.clear]
    default:
        return [Color.blue.opacity(0.1), Color.clear]
    }
}
