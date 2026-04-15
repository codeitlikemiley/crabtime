import SwiftUI

@MainActor
struct RightSidebarView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(RightSidebarTab.allCases, id: \.self) { tab in
                    Button {
                        store.selectRightSidebarTab(tab)
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(store.rightSidebarTab == tab ? CrabTimeTheme.Palette.ink : CrabTimeTheme.Palette.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(store.rightSidebarTab == tab ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill)
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        store.rightSidebarTab == tab ? CrabTimeTheme.Palette.strongDivider : CrabTimeTheme.Palette.divider,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .interactivePointer()
                }
            }

            Group {
                switch store.rightSidebarTab {
                case .inspector:
                    InspectorSidebarView()
                case .chat:
                    ChatSidebarView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                store.setExplorerKeyboardFocus(active: false)
            }
        )
        .paneCard()
    }
}
