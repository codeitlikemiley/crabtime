import SwiftUI

struct ExerciseCatalogView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EyebrowLabel(text: "Exercises", tint: CrabTimeTheme.Palette.textMuted)
                Spacer()
                Text("\(store.visibleExercises.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
            }

            if store.visibleExercises.isEmpty {
                WorkspaceEmptyStateView(
                    title: store.workspace == nil ? "No Exercises Yet" : "No Matching Exercises",
                    systemImage: "doc.text.magnifyingglass",
                    description: store.workspace == nil
                        ? "Import a Rust folder or source file to populate the browser."
                        : "Try a different search term or switch between open and done exercises."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(store.visibleExercises.enumerated()), id: \.element.id) { index, exercise in
                            ExerciseCard(
                                index: index,
                                exercise: exercise,
                                isSelected: store.selectedExercise?.id == exercise.id,
                                action: { store.selectAndOpenExercise(id: exercise.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct ExerciseCard: View {
    let index: Int
    let exercise: ExerciseDocument
    let isSelected: Bool
    let action: () -> Void

    private var passedCount: Int {
        exercise.checks.filter { $0.status == .passed }.count
    }

    private var statusTint: Color {
        if exercise.checks.contains(where: { $0.status == .failed }) {
            return CrabTimeTheme.Palette.ember
        }

        if !exercise.checks.isEmpty, exercise.checks.allSatisfy({ $0.status == .passed }) {
            return CrabTimeTheme.Palette.moss
        }

        return CrabTimeTheme.Palette.cyan
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let badgeText {
                            EyebrowLabel(text: badgeText, tint: badgeTint)
                        }

                        Text(exercise.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(CrabTimeTheme.Palette.ink)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Circle()
                        .fill(statusTint)
                        .frame(width: 10, height: 10)
                        .shadow(color: statusTint.opacity(0.35), radius: 8)
                }

                Text(exercise.summary)
                    .font(.footnote)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    MetaChip(text: exercise.sourceURL.deletingPathExtension().lastPathComponent, tint: roleTint)
                    MetaChip(text: "\(passedCount)/\(max(exercise.checks.count, 1)) passed", tint: statusTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? CrabTimeTheme.Palette.strongDivider : CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            CrabTimeTheme.Palette.selectionFill,
                            CrabTimeTheme.Palette.raisedFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CrabTimeTheme.Palette.raisedFill)
        }
    }

    private var badgeText: String? {
        if exercise.fileRole == .tests {
            return exercise.fileRole.title
        }

        switch exercise.difficulty {
        case .easy, .medium, .hard:
            return exercise.difficulty.title
        case .core, .kata, .unknown:
            return nil
        }
    }

    private var badgeTint: Color {
        if exercise.fileRole == .tests {
            return exercise.fileRole.tint
        }

        return exercise.difficulty.tint
    }

    private var roleTint: Color {
        exercise.fileRole == .tests ? exercise.fileRole.tint : CrabTimeTheme.Palette.textMuted
    }
}

private struct MetaChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.10)))
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
            .foregroundStyle(tint)
    }
}
