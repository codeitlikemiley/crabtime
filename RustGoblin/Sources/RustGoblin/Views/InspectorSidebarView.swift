import SwiftUI

struct InspectorSidebarView: View {
    @Environment(WorkspaceStore.self) private var store

    private var passedChecks: Int {
        store.currentChecks.filter { $0.status == .passed }.count
    }

    private var totalChecks: Int {
        store.currentChecks.count
    }

    private var completionRatio: Double {
        guard totalChecks > 0 else {
            return 0
        }

        return Double(passedChecks) / Double(totalChecks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Learning Assistant")
                    Text("Inspector")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                    Text("Hidden checks, hints, and run signals stay visible without stealing editor space.")
                        .font(.footnote)
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                }

                InspectorProgressCard(
                    statusTitle: statusTitle,
                    statusSymbol: statusSymbol,
                    statusTint: statusTint,
                    passedChecks: passedChecks,
                    totalChecks: totalChecks,
                    completionRatio: completionRatio,
                    errorCount: store.errorCount,
                    warningCount: store.warningCount
                )

                InspectorSection(title: "Hints") {
                    MarkdownDocumentView(
                        markdown: store.currentHintMarkdown,
                        sourceURL: store.selectedExercise?.hintURL ?? (store.isShowingMarkdownPreview ? store.selectedExplorerFileURL : nil),
                        sizingMode: .fill
                    )
                    .frame(minHeight: 220, maxHeight: 360)
                    .background(
                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                            .fill(RustGoblinTheme.Palette.subtleFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                            .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    )
                }

                InspectorSection(title: "Checks") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.currentChecks) { check in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(check.title, systemImage: check.symbolName)
                                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                                    Spacer()
                                    StatusBadge(text: statusText(for: check.status), tint: tint(for: check.status))
                                }
                                Text(check.detail)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                                    .fill(RustGoblinTheme.Palette.subtleFill)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if store.isExercismWorkspace {
                        Button(
                            store.isSubmittingExercism ? "Submitting…" : "Submit to Exercism",
                            systemImage: "paperplane.fill",
                            action: store.submitSelectedExerciseToExercism
                        )
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(RustGoblinTheme.Palette.buttonFill)
                        )
                        .overlay {
                            Capsule()
                                .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                        }
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                        .disabled(!store.canSubmitSelectedExerciseToExercism)
                        .interactivePointer()
                    }

                    if store.hasSolutionPreview {
                        Button(
                            store.isSolutionVisible ? "Hide Solution" : "Preview Solution",
                            systemImage: store.isSolutionVisible ? "eye.slash" : "lightbulb.max",
                            action: store.toggleSolutionVisibility
                        )
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(RustGoblinTheme.Palette.buttonFill)
                        )
                        .overlay {
                            Capsule()
                                .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                        }
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                        .interactivePointer()
                    }

                    if let solutionMarkdown = store.currentSolutionMarkdown {
                        InspectorSection(title: "Solution") {
                            MarkdownDocumentView(
                                markdown: "```rust\n\(solutionMarkdown)\n```",
                                sizingMode: .fill
                            )
                            .frame(minHeight: 180, maxHeight: 320)
                            .background(
                                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                                    .fill(RustGoblinTheme.Palette.subtleFill)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                            }
                            .clipShape(
                                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                            )
                        }
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        switch store.runState {
        case .idle:
            "Workspace ready"
        case .running:
            "Running current exercise"
        case .succeeded:
            "Run passed"
        case .failed:
            "Run needs fixes"
        }
    }

    private var statusSymbol: String {
        switch store.runState {
        case .idle:
            "sparkles"
        case .running:
            "hourglass"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch store.runState {
        case .idle:
            RustGoblinTheme.Palette.ink
        case .running:
            RustGoblinTheme.Palette.ember
        case .succeeded:
            RustGoblinTheme.Palette.moss
        case .failed:
            .red
        }
    }

    private func tint(for status: CheckStatus) -> Color {
        switch status {
        case .idle:
            RustGoblinTheme.Palette.ink.opacity(0.8)
        case .passed:
            RustGoblinTheme.Palette.moss
        case .failed:
            .red
        }
    }

    private func statusText(for status: CheckStatus) -> String {
        switch status {
        case .idle:
            "Idle"
        case .passed:
            "Pass"
        case .failed:
            "Fail"
        }
    }
}

private struct InspectorProgressCard: View {
    let statusTitle: String
    let statusSymbol: String
    let statusTint: Color
    let passedChecks: Int
    let totalChecks: Int
    let completionRatio: Double
    let errorCount: Int
    let warningCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Exercise Progress", tint: RustGoblinTheme.Palette.textMuted)

                    Text(totalChecks == 0 ? "No checks yet" : "\(passedChecks)/\(totalChecks) passed")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)

                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(statusTint)
                }

                Spacer()

                Text(totalChecks == 0 ? "--" : "\(Int(completionRatio * 100))%")
                    .font(.title2.weight(.black))
                    .foregroundStyle(RustGoblinTheme.Palette.panelTint)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(RustGoblinTheme.Palette.buttonFill)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    RustGoblinTheme.Palette.ember,
                                    RustGoblinTheme.Palette.cyan
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, proxy.size.width * completionRatio))
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                if errorCount > 0 {
                    StatusBadge(text: "\(errorCount) error", tint: .red)
                }
                if warningCount > 0 {
                    StatusBadge(text: "\(warningCount) warning", tint: RustGoblinTheme.Palette.panelTint)
                }
                if errorCount == 0, warningCount == 0 {
                    StatusBadge(text: "Signals clear", tint: RustGoblinTheme.Palette.moss)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.cornerRadius, style: .continuous)
                .fill(RustGoblinTheme.Palette.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.cornerRadius, style: .continuous)
                .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: title, tint: RustGoblinTheme.Palette.textMuted)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
