import SwiftUI

struct PaneCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .padding(RustGoblinTheme.Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.cornerRadius)
                        .fill(RustGoblinTheme.Palette.panelFill)
                )
                .glassEffect(
                    .regular.tint(RustGoblinTheme.Palette.glassTint),
                    in: .rect(cornerRadius: RustGoblinTheme.Layout.cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.cornerRadius)
                        .stroke(RustGoblinTheme.Palette.strongDivider, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.24), radius: 18, y: 8)
        } else {
            content
                .padding(RustGoblinTheme.Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.cornerRadius)
                        .fill(RustGoblinTheme.Palette.panelFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.cornerRadius)
                        .stroke(RustGoblinTheme.Palette.strongDivider, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.24), radius: 18, y: 8)
        }
    }
}

extension View {
    func paneCard() -> some View {
        modifier(PaneCardModifier())
    }
}
