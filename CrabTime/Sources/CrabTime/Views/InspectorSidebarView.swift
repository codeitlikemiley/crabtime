import SwiftUI

@MainActor
struct InspectorSidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(ProcessStore.self) private var processStore
    @Environment(ExercismStore.self) private var exercismStore
    @Environment(ExerciseSubmissionService.self) private var submissionService
    @State private var focusedCheckID: String?

    @MainActor
    private var testChecks: [ExerciseCheck] {
        store.currentChecks.filter { $0.id != "manual-run" }
    }

    @MainActor
    private var hasTestChecks: Bool {
        !testChecks.isEmpty
    }

    @MainActor
    private var testChecksHaveResults: Bool {
        testChecks.contains { $0.status != .idle }
    }

    @MainActor
    private var passedChecks: Int {
        testChecks.filter { $0.status == .passed }.count
    }

    @MainActor
    private var totalChecks: Int {
        testChecks.count
    }

    @MainActor
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
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                    Text("Run signals, test checks, and solution access without stealing editor space.")
                        .font(.footnote)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
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
                    errorCount: processStore.errorCount,
                    warningCount: processStore.warningCount
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
                            .fill(CrabTimeTheme.Palette.buttonFill)
                    )
                    .overlay {
                        Capsule()
                            .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                    }
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .interactivePointer()
                }

                if let provider = store.submissionProvider(exercismStore: exercismStore) {
                    SubmitActionCard(
                        provider: provider,
                        isSubmitting: submissionService.isSubmitting,
                        isCompleted: store.isCurrentExerciseCompleted,
                        feedbackURL: submissionService.submissionFeedbackURL,
                        verificationFeedback: submissionService.verificationFeedback,
                        onSubmit: {
                            submissionService.submit(using: store, processStore: processStore, exercismStore: exercismStore)
                        },
                        onUnmark: {
                            if let ex = store.selectedExercise {
                                store.unmarkExerciseCompleted(ex.id)
                            }
                        }
                    )
                }


                if hasTestChecks {
                    InspectorSection(title: "Checks") {
                        ScrollViewReader { scrollProxy in
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(testChecks) { check in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label(check.title, systemImage: check.symbolName)
                                                .foregroundStyle(CrabTimeTheme.Palette.ink)
                                            Spacer()
                                            StatusBadge(text: statusText(for: check.status), tint: tint(for: check.status))
                                        }
                                        Text(check.detail)
                                            .font(.callout.monospaced())
                                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                                            .fill(focusedCheckID == check.id
                                                ? CrabTimeTheme.Palette.panelTint.opacity(0.12)
                                                : CrabTimeTheme.Palette.subtleFill)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                                            .stroke(
                                                focusedCheckID == check.id
                                                    ? CrabTimeTheme.Palette.panelTint.opacity(0.5)
                                                    : CrabTimeTheme.Palette.divider,
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
                            .onChange(of: focusedCheckID) { _, newID in
                                if let id = newID {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        scrollProxy.scrollTo(id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    // Inspector key bridge — active only when lastFocusTarget == .inspectorList
                    .background(
                        InspectorKeyBridge(
                            isEnabled: store.lastFocusTarget == .inspectorList,
                            checks: testChecks,
                            focusedCheckID: focusedCheckID,
                            onFocus: { id in focusedCheckID = id },
                            onActivate: {
                                if let id = focusedCheckID,
                                   let check = testChecks.first(where: { $0.id == id }) {
                                    store.jumpToTestCheck(check)
                                }
                            }
                        )
                    )
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

    @MainActor
    private var statusTitle: String {
        switch processStore.runState {
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

    @MainActor
    private var statusSymbol: String {
        switch processStore.runState {
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

    @MainActor
    private var statusTint: Color {
        switch processStore.runState {
        case .idle:
            CrabTimeTheme.Palette.ink
        case .running:
            CrabTimeTheme.Palette.ember
        case .succeeded:
            CrabTimeTheme.Palette.moss
        case .failed:
            .red
        }
    }

    private func tint(for status: CheckStatus) -> Color {
        switch status {
        case .idle:
            CrabTimeTheme.Palette.ink.opacity(0.8)
        case .passed:
            CrabTimeTheme.Palette.moss
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

@MainActor
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
                    EyebrowLabel(text: "Exercise Progress", tint: CrabTimeTheme.Palette.textMuted)

                    Text(testSummaryText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)

                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(statusTint)
                }

                Spacer()

                Text(percentageText)
                    .font(.title2.weight(.black))
                    .foregroundStyle(CrabTimeTheme.Palette.panelTint)
            }

            if hasTestChecks && testChecksHaveResults {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CrabTimeTheme.Palette.buttonFill)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        CrabTimeTheme.Palette.ember,
                                        CrabTimeTheme.Palette.cyan
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
                    StatusBadge(text: "\(warningCount) warning", tint: CrabTimeTheme.Palette.panelTint)
                }
                if errorCount == 0, warningCount == 0 {
                    StatusBadge(text: "Signals clear", tint: CrabTimeTheme.Palette.moss)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.cornerRadius, style: .continuous)
                .fill(CrabTimeTheme.Palette.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.cornerRadius, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }
}

@MainActor
private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: title, tint: CrabTimeTheme.Palette.textMuted)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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

@MainActor
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

// MARK: - Inspector Keyboard Navigation Bridge

@MainActor
private struct InspectorKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let checks: [ExerciseCheck]
    let focusedCheckID: String?
    let onFocus: (String) -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(checks: checks, focusedCheckID: focusedCheckID, onFocus: onFocus, onActivate: onActivate)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.checks = checks
        context.coordinator.focusedCheckID = focusedCheckID
        context.coordinator.onFocus = onFocus
        context.coordinator.onActivate = onActivate
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator: @unchecked Sendable {
        var isEnabled: Bool
        var checks: [ExerciseCheck]
        var focusedCheckID: String?
        var onFocus: (String) -> Void
        var onActivate: () -> Void
        private var monitor: Any?

        init(checks: [ExerciseCheck], focusedCheckID: String?, onFocus: @escaping (String) -> Void, onActivate: @escaping () -> Void) {
            self.isEnabled = true
            self.checks = checks
            self.focusedCheckID = focusedCheckID
            self.onFocus = onFocus
            self.onActivate = onActivate
        }

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }

                // Don't intercept when a text view/field is editing
                let isTextEditing = MainActor.assumeIsolated {
                    NSApp.keyWindow?.firstResponder is NSTextView
                }
                guard !isTextEditing else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers?.lowercased()

                // j / Arrow Down / Ctrl+N → move selection down
                if modifiers.isEmpty, (chars == "j" || event.keyCode == 125) {
                    MainActor.assumeIsolated { self.moveSelection(by: 1) }
                    return nil
                }
                if modifiers == .control, chars == "n" {
                    MainActor.assumeIsolated { self.moveSelection(by: 1) }
                    return nil
                }

                // k / Arrow Up / Ctrl+P → move selection up
                if modifiers.isEmpty, (chars == "k" || event.keyCode == 126) {
                    MainActor.assumeIsolated { self.moveSelection(by: -1) }
                    return nil
                }
                if modifiers == .control, chars == "p" {
                    MainActor.assumeIsolated { self.moveSelection(by: -1) }
                    return nil
                }

                // Enter / Return → jump to test in editor
                if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                    MainActor.assumeIsolated { self.onActivate() }
                    return nil
                }

                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor
        private func moveSelection(by delta: Int) {
            guard !checks.isEmpty else { return }
            let currentIndex = checks.firstIndex(where: { $0.id == focusedCheckID }) ?? -1
            let nextIndex = max(0, min(checks.count - 1, currentIndex + delta))
            onFocus(checks[nextIndex].id)
        }
    }
}

@MainActor
private struct SubmitActionCard: View {
    let provider: any ExerciseSubmissionProvider
    let isSubmitting: Bool
    let isCompleted: Bool
    let feedbackURL: URL?
    /// AI FAIL reason — shown below the button when verification was rejected.
    var verificationFeedback: String? = nil
    let onSubmit: () -> Void
    /// Called when the user taps the “Reopen” button to reset a wrongly-marked exercise.
    var onUnmark: (() -> Void)? = nil

    var body: some View {
        if isCompleted {
            if provider.supportsRemoteSubmit {
                // Remote provider: show feedback URL + re-submit icon
                HStack(spacing: 8) {
                    if let url = feedbackURL {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            Label("View Feedback", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.plain)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                        .overlay {
                            Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                        }
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                        .interactivePointer()
                    }

                    Button(action: onSubmit) {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                    .overlay {
                        Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                    }
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .disabled(isSubmitting)
                    .help("Submit Update")
                    .interactivePointer()
                }
            } else {
                // Local provider: Done badge + small Reopen affordance
                HStack(spacing: 8) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.moss)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Capsule().fill(CrabTimeTheme.Palette.moss.opacity(0.12)))
                        .overlay { Capsule().stroke(CrabTimeTheme.Palette.moss.opacity(0.4), lineWidth: 1) }

                    if let unmark = onUnmark {
                        Button(action: unmark) {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.plain)
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                        .overlay { Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1) }
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        .help("Reopen — reset to Open so you can re-verify")
                        .interactivePointer()
                    }
                }
            }
        } else {
            // Not yet completed: show submit button
            Button(action: onSubmit) {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: provider.actionIcon)
                    }
                    Text(isSubmitting ? "Submitting…" : provider.actionLabel)
                }
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
            .overlay {
                Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
            .foregroundStyle(CrabTimeTheme.Palette.ink)
            .disabled(isSubmitting)
            .interactivePointer()
        }

        // AI FAIL reason — only visible for local providers after a failed verification
        if !isCompleted, !provider.supportsRemoteSubmit, let feedback = verificationFeedback {
            Text(feedback)
                .font(.caption)
                .foregroundStyle(CrabTimeTheme.Palette.ember)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

