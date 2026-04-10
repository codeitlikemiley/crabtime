import SwiftUI

struct InspectorSidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var focusedCheckID: String?

    private var testChecks: [ExerciseCheck] {
        store.currentChecks.filter { $0.id != "manual-run" }
    }

    private var hasTestChecks: Bool {
        !testChecks.isEmpty
    }

    private var testChecksHaveResults: Bool {
        testChecks.contains { $0.status != .idle }
    }

    private var passedChecks: Int {
        testChecks.filter { $0.status == .passed }.count
    }

    private var totalChecks: Int {
        testChecks.count
    }

    private var completionRatio: Double {
        guard totalChecks > 0, testChecksHaveResults else {
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
                    Text("Run signals, test checks, and solution access without stealing editor space.")
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
                    hasTestChecks: hasTestChecks,
                    testChecksHaveResults: testChecksHaveResults,
                    errorCount: store.errorCount,
                    warningCount: store.warningCount
                )

                if store.hasSolutionPreview {
                    Button(
                        "View Solution",
                        systemImage: "lightbulb.max",
                        action: store.openSolutionFile
                    )
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
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

                if store.isExercismWorkspace, let slug = store.workspace?.rootURL.lastPathComponent {
                    if store.exercismCompletedExercises.contains(slug) {
                        HStack(spacing: 8) {
                            Button(action: {
                                if let url = URL(string: "https://exercism.org/tracks/rust/exercises/\(slug)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                Label("View on Exercism", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(RustGoblinTheme.Palette.buttonFill)
                            )
                            .overlay {
                                Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                            }
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                            .interactivePointer()

                            Button(action: store.submitSelectedExerciseToExercism) {
                                if store.isSubmittingExercism {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(RustGoblinTheme.Palette.buttonFill)
                            )
                            .overlay {
                                Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                            }
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                            .disabled(!store.canSubmitSelectedExerciseToExercism)
                            .help("Submit Update")
                            .interactivePointer()
                        }
                    } else {
                        Button(action: store.submitSelectedExerciseToExercism) {
                            HStack(spacing: 6) {
                                if store.isSubmittingExercism {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(store.isSubmittingExercism ? "Submitting…" : "Submit to Exercism")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(RustGoblinTheme.Palette.buttonFill)
                        )
                        .overlay {
                            Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                        }
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                        .disabled(!store.canSubmitSelectedExerciseToExercism)
                        .interactivePointer()
                    }
                }

                if hasTestChecks {
                    InspectorSection(title: "Checks") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(testChecks) { check in
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
                                        .fill(focusedCheckID == check.id
                                            ? RustGoblinTheme.Palette.panelTint.opacity(0.12)
                                            : RustGoblinTheme.Palette.subtleFill)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                                        .stroke(
                                            focusedCheckID == check.id
                                                ? RustGoblinTheme.Palette.panelTint.opacity(0.5)
                                                : RustGoblinTheme.Palette.divider,
                                            lineWidth: focusedCheckID == check.id ? 1.5 : 1
                                        )
                                }
                                .id(check.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    focusedCheckID = check.id
                                    store.jumpToTestCheck(check)
                                }
                                .interactivePointer()
                            }
                        }
                    }
                }

            }
        }
        .task(id: store.inspectorListFocusToken) {
            guard store.inspectorListFocusToken > 0 else { return }
            if let firstCheck = testChecks.first {
                focusedCheckID = firstCheck.id
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
    let hasTestChecks: Bool
    let testChecksHaveResults: Bool
    let errorCount: Int
    let warningCount: Int

    private var testSummaryText: String {
        if !hasTestChecks {
            return "No tests"
        }
        if !testChecksHaveResults {
            return "Not tested yet"
        }
        return "\(passedChecks)/\(totalChecks) passed"
    }

    private var percentageText: String {
        if !hasTestChecks || !testChecksHaveResults {
            return "--"
        }
        return "\(Int(completionRatio * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Exercise Progress", tint: RustGoblinTheme.Palette.textMuted)

                    Text(testSummaryText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)

                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(statusTint)
                }

                Spacer()

                Text(percentageText)
                    .font(.title2.weight(.black))
                    .foregroundStyle(RustGoblinTheme.Palette.panelTint)
            }

            if hasTestChecks && testChecksHaveResults {
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
            }

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
