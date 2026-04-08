import SwiftUI

struct WorkspaceRailView: View {
    @Environment(WorkspaceStore.self) private var store

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
                    isActive: store.sidebarMode == .exercises,
                    action: { store.selectSidebarMode(.exercises) }
                )

                dockButton(
                    systemImage: "folder",
                    help: "Show explorer",
                    isActive: store.sidebarMode == .explorer,
                    action: { store.selectSidebarMode(.explorer) }
                )
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 8) {
                StatusDot(isActive: store.runState == .running, tint: RustGoblinTheme.Palette.cyan)
                StatusDot(isActive: store.runState == .failed, tint: RustGoblinTheme.Palette.ember)
                StatusDot(isActive: store.runState == .succeeded, tint: RustGoblinTheme.Palette.moss)
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
                .fill(RustGoblinTheme.Palette.divider)
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
                                RustGoblinTheme.Palette.ember,
                                RustGoblinTheme.Palette.panelTint
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
            .shadow(color: RustGoblinTheme.Palette.ember.opacity(0.25), radius: 10, y: 4)
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
