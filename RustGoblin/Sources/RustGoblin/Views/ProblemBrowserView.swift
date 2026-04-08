import SwiftUI

struct ProblemBrowserView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Group {
            if store.sidebarMode == .explorer {
                WorkspaceExplorerView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel(text: "Exercise Library")

                            Text(store.workspace?.title ?? "Imported Exercises")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(RustGoblinTheme.Palette.ink)

                            Text("Browse imported prompts, switch between exercises, and keep the brief close to the code.")
                                .font(.footnote)
                                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        WorkspaceSidebarToolbar()
                    }

                    ProblemSearchField(text: $store.searchText, resultCount: store.visibleExercises.count)
                    DifficultyFilterStrip()

                    VSplitView {
                        ExerciseCatalogView()
                            .frame(minHeight: 250)

                        ProblemStatementView()
                            .frame(minHeight: 320)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .paneCard()
            }
        }
    }
}

private struct ProblemSearchField: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var text: String
    let resultCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RustGoblinTheme.Palette.textMuted)

            TextField("Search exercises", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(RustGoblinTheme.Palette.ink)
                .tint(RustGoblinTheme.Palette.panelTint)

            Text("\(resultCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
        }
        .onChange(of: text) { _, _ in
            store.persistSearchTextChange()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .fill(RustGoblinTheme.Palette.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
        }
    }
}
