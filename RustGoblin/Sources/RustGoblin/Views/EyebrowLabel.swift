import SwiftUI

struct EyebrowLabel: View {
    let text: String
    var tint: Color = RustGoblinTheme.Palette.panelTint

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(tint)
    }
}
