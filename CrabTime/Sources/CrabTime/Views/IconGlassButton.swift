import SwiftUI

struct IconGlassButton: View {
    let systemImage: String
    let helpText: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? CrabTimeTheme.Palette.panelTint : CrabTimeTheme.Palette.ink)
                .frame(
                    width: CrabTimeTheme.Layout.iconButtonSize,
                    height: CrabTimeTheme.Layout.iconButtonSize
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? CrabTimeTheme.Palette.buttonActiveFill : CrabTimeTheme.Palette.buttonFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? CrabTimeTheme.Palette.panelTint.opacity(0.30) : CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(isActive ? 0.26 : 0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .interactivePointer()
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
