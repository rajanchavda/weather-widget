import SwiftUI

struct TemperatureLineView: View {
    let temps: [Double]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let minTemp = temps.min() ?? 0.0
        let maxTemp = temps.max() ?? 100.0
        let tempRange = max(maxTemp - minTemp, 1.0)

        let lineGradient = LinearGradient(
            colors: temps.map { getTemperatureColor($0) },
            startPoint: .leading,
            endPoint: .trailing
        )

        Path { path in
            let stepX = width / CGFloat(temps.count - 1)

            for i in 0..<temps.count {
                let x = CGFloat(i) * stepX
                let normalizedTemp = (temps[i] - minTemp) / tempRange
                let yOffset = CGFloat(normalizedTemp) * 4.0
                let y = height - 1.0 - yOffset

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
}
