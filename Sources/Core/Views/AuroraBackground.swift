import SwiftUI

struct AuroraBackground: View {
    let colors: [Color]
    let height: CGFloat

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height / 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
