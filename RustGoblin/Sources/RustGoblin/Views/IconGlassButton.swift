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
                .foregroundStyle(isActive ? RustGoblinTheme.Palette.panelTint : RustGoblinTheme.Palette.ink)
                .frame(
                    width: RustGoblinTheme.Layout.iconButtonSize,
                    height: RustGoblinTheme.Layout.iconButtonSize
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? RustGoblinTheme.Palette.buttonActiveFill : RustGoblinTheme.Palette.buttonFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? RustGoblinTheme.Palette.panelTint.opacity(0.30) : RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(isActive ? 0.26 : 0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .interactivePointer()
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
