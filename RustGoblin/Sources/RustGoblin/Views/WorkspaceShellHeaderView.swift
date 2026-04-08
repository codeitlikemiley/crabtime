import SwiftUI

struct WorkspaceShellHeaderView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack {
            Label("RustGoblin", systemImage: "chevron.left.slash.chevron.right")
                .font(.headline)
                .foregroundStyle(RustGoblinTheme.Palette.ink)

            Spacer()

            Text(store.workspace?.title ?? "Flexible Workspace")
                .font(.headline)
                .foregroundStyle(RustGoblinTheme.Palette.textMuted)

            Spacer()

            HStack(spacing: 8) {
                SmallShellIcon(systemImage: "square.and.arrow.up")
                SmallShellIcon(systemImage: "square.grid.2x2")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: RustGoblinTheme.Layout.shellHeaderHeight)
        .background(
            Capsule()
                .fill(RustGoblinTheme.Palette.subtleFill)
        )
        .overlay {
            Capsule()
                .stroke(RustGoblinTheme.Palette.strongDivider, lineWidth: 1)
        }
    }
}

private struct SmallShellIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RustGoblinTheme.Palette.ink.opacity(0.9))
            .frame(width: 24, height: 24)
    }
}
