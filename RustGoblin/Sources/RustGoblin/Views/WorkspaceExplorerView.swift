import SwiftUI

struct WorkspaceExplorerView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Explorer")

                    Text(store.workspace?.title ?? "Workspace Files")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)

                    Text("Browse the imported folder tree and open any file in the main workspace preview.")
                        .font(.footnote)
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                WorkspaceSidebarToolbar()
            }

            if store.currentFileTree.isEmpty {
                WorkspaceEmptyStateView(
                    title: "No Files Loaded",
                    systemImage: "folder",
                    description: "Import a Rust folder to inspect its file tree here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.currentFileTree) { node in
                            WorkspaceExplorerNodeView(node: node, depth: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
    }
}

private struct WorkspaceExplorerNodeView: View {
    @Environment(WorkspaceStore.self) private var store

    let node: WorkspaceFileNode
    let depth: Int
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if node.isDirectory {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)

                        Image(systemName: "folder")
                            .foregroundStyle(RustGoblinTheme.Palette.panelTint)

                        Text(node.name)
                            .foregroundStyle(RustGoblinTheme.Palette.ink)

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .interactivePointer()

                if isExpanded {
                    ForEach(node.children) { child in
                        WorkspaceExplorerNodeView(node: child, depth: depth + 1)
                    }
                }
            } else {
                Button {
                    store.openExplorerFile(node.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .foregroundStyle(fileTint)

                        Text(node.name)
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14 + 24)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(fileBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(fileBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }
        }
    }

    private var isSelected: Bool {
        store.selectedExplorerFileURL == node.url
    }

    private var fileTint: Color {
        isSelected ? RustGoblinTheme.Palette.panelTint : RustGoblinTheme.Palette.textMuted
    }

    private var fileBorder: Color {
        isSelected ? RustGoblinTheme.Palette.strongDivider : .clear
    }

    private var fileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? RustGoblinTheme.Palette.selectionFill : Color.clear)
    }
}
