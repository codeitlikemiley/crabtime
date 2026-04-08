import SwiftUI

struct ProblemStatementView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedExercise = store.selectedExercise {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Challenge Brief", tint: RustGoblinTheme.Palette.textMuted)

                    Text(selectedExercise.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)

                    Text(selectedExercise.summary)
                        .font(.footnote)
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                }

                ScrollView {
                    MarkdownDocumentView(
                        markdown: store.currentProblemMarkdown,
                        sourceURL: selectedExercise.readmeURL
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                        .fill(RustGoblinTheme.Palette.raisedFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                        .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
            } else {
                WorkspaceEmptyStateView(
                    title: "Select an Exercise",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: "Imported exercises will appear here together with their README-driven problem statements."
                )
            }
        }
    }
}
