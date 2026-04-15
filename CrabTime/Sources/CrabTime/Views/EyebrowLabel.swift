import SwiftUI

@MainActor
struct EyebrowLabel: View {
    let text: String
    var tint: Color = CrabTimeTheme.Palette.panelTint

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(tint)
    }
}
