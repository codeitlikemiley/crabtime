import SwiftUI

@MainActor
struct WorkspaceEmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(CrabTimeTheme.Palette.subtleFill)
                )
                .overlay {
                    Circle()
                        .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
