import SwiftUI

struct WorkspaceRailView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Environment(ProcessStore.self) private var processStore

    var body: some View {
        VStack(spacing: 18) {
            MiniRailBadge(systemImage: "chevron.left.slash.chevron.right")
                .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                dockButton(
                    systemImage: "folder.badge.plus",
                    help: "Import exercises",
                    isActive: false,
                    action: store.openWorkspace
                )

                dockButton(
                    systemImage: "list.bullet.rectangle.portrait",
                    help: "Show exercises",
                    isActive: navigationStore.sidebarMode == .exercises,
                    action: { navigationStore.sidebarMode = .exercises }
                )

                dockButton(
                    systemImage: "folder",
                    help: "Show explorer",
                    isActive: navigationStore.sidebarMode == .explorer,
                    action: { navigationStore.sidebarMode = .explorer }
                )

                dockButton(
                    systemImage: "checklist",
                    help: "Show TODOs",
                    isActive: navigationStore.sidebarMode == .todos,
                    action: { navigationStore.sidebarMode = .todos }
                )

                dockButton(
                    systemImage: "graduationcap",
                    help: "Browse Exercism",
                    isActive: navigationStore.sidebarMode == .exercism,
                    action: { navigationStore.sidebarMode = .exercism }
                )
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 8) {
                StatusDot(isActive: processStore.runState == .running, tint: CrabTimeTheme.Palette.cyan)
                StatusDot(isActive: processStore.runState == .failed, tint: CrabTimeTheme.Palette.ember)
                StatusDot(isActive: processStore.runState == .succeeded, tint: CrabTimeTheme.Palette.moss)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxHeight: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .padding(.horizontal, 6)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CrabTimeTheme.Palette.divider)
                .frame(width: 1)
                .padding(.vertical, 8)
        }
    }

    private func dockButton(
        systemImage: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        IconGlassButton(
            systemImage: systemImage,
            helpText: help,
            isActive: isActive,
            action: action
        )
    }
}

private struct MiniRailBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CrabTimeTheme.Palette.ember,
                                CrabTimeTheme.Palette.panelTint
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: CrabTimeTheme.Palette.ember.opacity(0.25), radius: 10, y: 4)
    }
}

private struct StatusDot: View {
    let isActive: Bool
    let tint: Color

    var body: some View {
        Circle()
            .fill(isActive ? tint : Color.white.opacity(0.10))
            .frame(width: 8, height: 8)
            .shadow(color: isActive ? tint.opacity(0.35) : .clear, radius: 6)
    }
}
