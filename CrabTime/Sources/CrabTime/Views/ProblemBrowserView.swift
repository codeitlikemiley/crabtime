import SwiftUI

struct ProblemBrowserView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore

    var body: some View {
        @Bindable var store = store

        Group {
            switch navigationStore.sidebarMode {
            case .explorer:
                WorkspaceExplorerView()
            case .todos:
                TodoExplorerView()
            case .exercism:
                ExercismBrowserView()
            case .exercises:
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        EyebrowLabel(text: "Exercise Library")

                        Text(store.workspace?.title ?? "Imported Exercises")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(CrabTimeTheme.Palette.ink)

                        Text("Browse imported prompts, switch between exercises, and keep the brief close to the code.")
                            .font(.footnote)
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ProblemSearchField(text: $store.searchText, resultCount: store.visibleExercises.count)
                    DifficultyFilterStrip()

                    ExerciseCatalogView()
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .paneCard()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if navigationStore.sidebarMode != .explorer {
                    store.setExplorerKeyboardFocus(active: false)
                }
            }
        )
    }
}

private struct ProblemSearchField: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Binding var text: String
    let resultCount: Int
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)

            TextField("Search exercises", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .tint(CrabTimeTheme.Palette.panelTint)
                .focused($isFocused)
                .onSubmit {
                    store.openFirstVisibleExercise()
                }

            Text("\(resultCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
        }
        .onChange(of: text) { _, _ in
            store.persistSearchTextChange()
        }
        .task(id: store.exerciseSearchFocusToken) {
            guard store.exerciseSearchFocusToken > 0 else {
                return
            }
            isFocused = true
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .fill(CrabTimeTheme.Palette.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }
}
