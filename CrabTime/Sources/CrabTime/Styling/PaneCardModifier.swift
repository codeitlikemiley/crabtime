import SwiftUI

struct PaneCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .padding(CrabTimeTheme.Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.cornerRadius)
                    .fill(CrabTimeTheme.Palette.panelFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.cornerRadius)
                    .stroke(CrabTimeTheme.Palette.strongDivider, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 18, y: 8)
    }
}

extension View {
    func paneCard() -> some View {
        modifier(PaneCardModifier())
    }
}
