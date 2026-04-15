import SwiftUI

@MainActor
struct WorkbenchBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CrabTimeTheme.Palette.backgroundTop,
                    CrabTimeTheme.Palette.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(CrabTimeTheme.Palette.glowTop.opacity(0.16))
                .blur(radius: 160)
                .frame(width: 380, height: 380)
                .offset(x: -300, y: -240)

            Circle()
                .fill(CrabTimeTheme.Palette.glowBottom.opacity(0.14))
                .blur(radius: 180)
                .frame(width: 460, height: 460)
                .offset(x: 430, y: 260)

            RoundedRectangle(cornerRadius: 180)
                .fill(
                    LinearGradient(
                        colors: [
                            CrabTimeTheme.Palette.panelTint.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 120)
                .frame(width: 620, height: 220)
                .offset(x: 120, y: -320)
        }
    }
}
