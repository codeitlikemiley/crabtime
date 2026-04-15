import SwiftUI

@MainActor
struct ConsolePanelView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Environment(ProcessStore.self) private var processStore

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Terminal Output", tint: CrabTimeTheme.Palette.textMuted)
                    Text("Feedback Loop")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                }

                Spacer()

                HStack(spacing: 8) {
                    ConsoleTabButton(
                        title: "Output",
                        isSelected: navigationStore.selectedConsoleTab == .output,
                        badgeText: nil
                    ) {
                        navigationStore.selectedConsoleTab = .output
                    }

                    ConsoleTabButton(
                        title: "Diagnostics",
                        isSelected: navigationStore.selectedConsoleTab == .diagnostics,
                        badgeText: processStore.diagnosticsCount == 0 ? nil : "\(processStore.diagnosticsCount)",
                        accentColor: processStore.errorCount > 0 ? Color.red : CrabTimeTheme.Palette.ember
                    ) {
                        navigationStore.selectedConsoleTab = .diagnostics
                    }

                    ConsoleTabButton(
                        title: "Session",
                        isSelected: navigationStore.selectedConsoleTab == .session,
                        badgeText: nil
                    ) {
                        navigationStore.selectedConsoleTab = .session
                    }

                    ConsoleTabButton(
                        title: "AI Runtime",
                        isSelected: navigationStore.selectedConsoleTab == .aiRuntime,
                        badgeText: processStore.aiRuntimeToolCalls.isEmpty ? nil : "\(processStore.aiRuntimeToolCalls.count)",
                        accentColor: processStore.aiRuntimeTransport == .acp ? CrabTimeTheme.Palette.cyan : CrabTimeTheme.Palette.textMuted
                    ) {
                        navigationStore.selectedConsoleTab = .aiRuntime
                    }

                    // Copy session log to clipboard when session tab is active
                    if navigationStore.selectedConsoleTab == .session && !store.sessionLog.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                store.sessionLog.joined(separator: "\n"),
                                forType: .string
                            )
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                                .overlay { Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1) }
                                .foregroundStyle(CrabTimeTheme.Palette.ink)
                        }
                        .buttonStyle(.plain)
                        .interactivePointer()
                        .help("Copy session log to clipboard")
                    }

                    if navigationStore.selectedConsoleTab == .aiRuntime && !processStore.aiRuntimeEvents.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                processStore.aiRuntimeEvents.joined(separator: "\n"),
                                forType: .string
                            )
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                                .overlay { Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1) }
                                .foregroundStyle(CrabTimeTheme.Palette.ink)
                        }
                        .buttonStyle(.plain)
                        .interactivePointer()
                        .help("Copy AI runtime events to clipboard")
                    }

                    IconGlassButton(
                        systemImage: "trash",
                        helpText: "Clear output",
                        action: { store.clearConsoleOutput() }
                    )

                    IconGlassButton(
                        systemImage: navigationStore.isTerminalMaximized ? "arrow.down.right.and.arrow.up.left" : "rectangle.bottomthird.inset.filled",
                        helpText: navigationStore.isTerminalMaximized ? "Return to split view" : "Maximize terminal",
                        isActive: navigationStore.isTerminalMaximized,
                        action: navigationStore.toggleTerminalMaximize
                    )

                    IconGlassButton(
                        systemImage: "terminal",
                        helpText: "Hide terminal",
                        isActive: true,
                        action: navigationStore.toggleTerminalVisibility
                    )
                }
            }

            Group {
                switch navigationStore.selectedConsoleTab {
                case .output:
                    ScrollView {
                        if store.consoleOutput.isEmpty {
                            ANSITextView(text: "Output appears here.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(store.consoleOutput.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                                    ANSITextView(text: line)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .diagnostics:
                    if processStore.diagnostics.isEmpty {
                        WorkspaceEmptyStateView(
                            title: "No Diagnostics",
                            systemImage: "checkmark.circle",
                            description: "Compiler warnings and errors appear here after a run."
                        )
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(processStore.diagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                                        DiagnosticCard(
                                            diagnostic: diagnostic,
                                            isSelected: index == processStore.selectedDiagnosticIndex
                                        ) {
                                            if let line = diagnostic.line {
                                                store.goToLine(line)
                                            }
                                        }
                                        .id(diagnostic.id)
                                    }
                                }
                            }
                            .onChange(of: processStore.selectedDiagnosticIndex) { _, newValue in
                                if processStore.diagnostics.indices.contains(newValue) {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        scrollProxy.scrollTo(processStore.diagnostics[newValue].id, anchor: .center)
                                    }
                                }
                            }
                        }
                        .background(
                            DiagnosticsKeyBridge(
                                isEnabled: navigationStore.selectedConsoleTab == .diagnostics,
                                onMoveUp: { processStore.moveDiagnosticSelectionUp() },
                                onMoveDown: { processStore.moveDiagnosticSelectionDown() },
                                onActivate: { processStore.activateSelectedDiagnostic(using: store) }
                            )
                        )
                    }
                case .session:
                    if store.sessionLog.isEmpty {
                        WorkspaceEmptyStateView(
                            title: "No Session Events",
                            systemImage: "clock",
                            description: "Actions like running exercises, creating challenges, and AI enrichment appear here."
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(store.sessionLog.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .aiRuntime:
                    AIRuntimeConsoleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                    .fill(CrabTimeTheme.Palette.terminalFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                    .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
    }
}

private struct AIRuntimeConsoleView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Environment(ProcessStore.self) private var processStore

    var body: some View {
        if processStore.aiRuntimeEvents.isEmpty && processStore.aiRuntimeToolCalls.isEmpty && processStore.aiRuntimeTransport == nil {
            WorkspaceEmptyStateView(
                title: "No AI Runtime Activity",
                systemImage: "bolt.horizontal.circle",
                description: "ACP auth state, warm session details, and live tool calls will appear here when chat starts."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    runtimeSummaryCard
                    runtimeActions

                    if !processStore.aiRuntimeToolCalls.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tool Calls")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(CrabTimeTheme.Palette.ink)

                            ForEach(processStore.aiRuntimeToolCalls) { tool in
                                toolCallCard(tool)
                            }
                        }
                    }

                    if !processStore.aiRuntimeEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Runtime Events")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(CrabTimeTheme.Palette.ink)

                            ForEach(Array(processStore.aiRuntimeEvents.enumerated()), id: \.offset) { _, event in
                                Text(event)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var runtimeSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Runtime")
                .font(.headline.weight(.bold))
                .foregroundStyle(CrabTimeTheme.Palette.ink)

            runtimeRow("Provider", processStore.aiRuntimeProviderTitle)
            runtimeRow("Transport", processStore.aiRuntimeTransport?.title ?? "Unknown")
            runtimeRow("Model", processStore.aiRuntimeModel.isEmpty ? "Unknown" : processStore.aiRuntimeModel)
            runtimeRow("Process", processStore.aiRuntimeProcessStatus)
            runtimeRow("Auth", processStore.aiRuntimeAuthStatus)
            runtimeRow("Session", processStore.aiRuntimeSessionID ?? "None")

            if let logPath = processStore.aiRuntimeLogPath {
                runtimeRow("Logs", logPath)
            }
            if let lastError = processStore.aiRuntimeLastError, !lastError.isEmpty {
                runtimeRow("Last Error", lastError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                .fill(CrabTimeTheme.Palette.subtleFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }

    private var runtimeActions: some View {
        HStack(spacing: 8) {
            Button("Reconnect ACP") {
                processStore.reconnectCurrentAITransport(using: store)
            }
            .disabled(processStore.aiRuntimeTransport != .acp)

            Button("Reset Warm Session") {
                processStore.resetCurrentWarmAISession(using: store)
            }
            .disabled(processStore.aiRuntimeTransport != .acp)

            Button("Open ACP Logs") {
                processStore.openAIRuntimeLogs()
            }
            .disabled(processStore.aiRuntimeLogPath == nil)

            Button("Copy Runtime Report") {
                copyToPasteboard(runtimeReportText)
            }
            .disabled(runtimeReportText.isEmpty)
        }
        .buttonStyle(.bordered)
    }

    private var runtimeReportText: String {
        var lines: [String] = [
            "Provider: \(processStore.aiRuntimeProviderTitle)",
            "Transport: \(processStore.aiRuntimeTransport?.title ?? "Unknown")",
            "Model: \(processStore.aiRuntimeModel.isEmpty ? "Unknown" : processStore.aiRuntimeModel)",
            "Process: \(processStore.aiRuntimeProcessStatus)",
            "Auth: \(processStore.aiRuntimeAuthStatus)",
            "Session: \(processStore.aiRuntimeSessionID ?? "None")"
        ]

        if let logPath = processStore.aiRuntimeLogPath, !logPath.isEmpty {
            lines.append("Logs: \(logPath)")
        }
        if let lastError = processStore.aiRuntimeLastError, !lastError.isEmpty {
            lines.append("Last Error: \(lastError)")
        }
        if !processStore.aiRuntimeToolCalls.isEmpty {
            lines.append("")
            lines.append("Tool Calls:")
            lines.append(contentsOf: processStore.aiRuntimeToolCalls.map { "\($0.title) [\($0.status)] \($0.id)" })
        }
        if !processStore.aiRuntimeEvents.isEmpty {
            lines.append("")
            lines.append("Runtime Events:")
            lines.append(contentsOf: processStore.aiRuntimeEvents)
        }

        return lines.joined(separator: "\n")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func runtimeRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .textSelection(.enabled)
        }
    }

    private func toolCallCard(_ tool: AIToolCallSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tool.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)

                Spacer()

                Text(tool.status)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(tool.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColor(tool.status).opacity(0.14)))
            }

            Text(tool.id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                .fill(CrabTimeTheme.Palette.subtleFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed", "complete", "finished", "succeeded":
            CrabTimeTheme.Palette.moss
        case "failed", "error":
            .red
        case "started", "pending", "in_progress", "running", "updated":
            CrabTimeTheme.Palette.cyan
        default:
            CrabTimeTheme.Palette.ember
        }
    }
}

// MARK: - Diagnostic Card (clickable)

private struct DiagnosticCard: View {
    let diagnostic: Diagnostic
    var isSelected: Bool = false
    let onNavigate: () -> Void

    var body: some View {
        Button(action: onNavigate) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(
                        diagnostic.severity == .error ? "Error" : "Warning",
                        systemImage: diagnostic.severity == .error
                            ? "xmark.octagon.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(diagnostic.severity == .error ? .red : CrabTimeTheme.Palette.ember)

                    Spacer()

                    if let line = diagnostic.line {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(size: 10))
                            Text("Line \(line)")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CrabTimeTheme.Palette.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(CrabTimeTheme.Palette.cyan.opacity(0.12))
                        )
                    }
                }

                Text(diagnostic.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                    .fill(
                        isSelected
                            ? CrabTimeTheme.Palette.ember.opacity(0.12)
                            : (diagnostic.severity == .error
                                ? Color.red.opacity(0.06)
                                : CrabTimeTheme.Palette.subtleFill)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                    .stroke(
                        isSelected
                            ? CrabTimeTheme.Palette.ember.opacity(0.6)
                            : (diagnostic.severity == .error
                                ? Color.red.opacity(0.25)
                                : CrabTimeTheme.Palette.divider),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}

// MARK: - ANSI Text Rendering

private struct ANSITextView: View {
    let text: String

    var body: some View {
        Text(parseANSI(text))
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }

    private func parseANSI(_ input: String) -> AttributedString {
        var result = AttributedString()
        var currentColor: Color = CrabTimeTheme.Palette.ink
        var isBold = false
        var remaining = input[...]

        while !remaining.isEmpty {
            // Find next ESC sequence
            if let escRange = remaining.range(of: "\u{1B}[") {
                // Add text before ESC
                let prefix = remaining[remaining.startIndex..<escRange.lowerBound]
                if !prefix.isEmpty {
                    var attr = AttributedString(String(prefix))
                    attr.foregroundColor = currentColor
                    if isBold {
                        attr.font = .system(.body, design: .monospaced).bold()
                    }
                    result += attr
                }

                // Parse the escape code
                remaining = remaining[escRange.upperBound...]
                if let mIndex = remaining.firstIndex(of: "m") {
                    let codeStr = remaining[remaining.startIndex..<mIndex]
                    let codes = codeStr.split(separator: ";").compactMap { Int($0) }

                    for code in codes {
                        switch code {
                        case 0:     // Reset
                            currentColor = CrabTimeTheme.Palette.ink
                            isBold = false
                        case 1:     // Bold
                            isBold = true
                        case 31:    // Red
                            currentColor = Color(red: 0.95, green: 0.35, blue: 0.35)
                        case 32:    // Green
                            currentColor = Color(red: 0.35, green: 0.85, blue: 0.45)
                        case 33:    // Yellow
                            currentColor = Color(red: 0.95, green: 0.80, blue: 0.30)
                        case 34:    // Blue
                            currentColor = Color(red: 0.45, green: 0.65, blue: 0.95)
                        case 35:    // Magenta
                            currentColor = Color(red: 0.85, green: 0.50, blue: 0.90)
                        case 36:    // Cyan
                            currentColor = Color(red: 0.45, green: 0.85, blue: 0.90)
                        case 37, 97:  // White / bright white
                            currentColor = Color(red: 0.95, green: 0.95, blue: 0.97)
                        case 90:    // Bright black (gray)
                            currentColor = Color(red: 0.55, green: 0.55, blue: 0.60)
                        case 91:    // Bright red
                            currentColor = Color(red: 1.0, green: 0.40, blue: 0.40)
                        case 92:    // Bright green
                            currentColor = Color(red: 0.40, green: 0.95, blue: 0.50)
                        case 93:    // Bright yellow
                            currentColor = Color(red: 1.0, green: 0.90, blue: 0.40)
                        case 94:    // Bright blue
                            currentColor = Color(red: 0.55, green: 0.75, blue: 1.0)
                        case 95:    // Bright magenta
                            currentColor = Color(red: 0.95, green: 0.60, blue: 1.0)
                        case 96:    // Bright cyan
                            currentColor = Color(red: 0.55, green: 0.95, blue: 1.0)
                        default:
                            break
                        }
                    }

                    remaining = remaining[remaining.index(after: mIndex)...]
                }
            } else {
                // No more ESC sequences — add remainder
                var attr = AttributedString(String(remaining))
                attr.foregroundColor = currentColor
                if isBold {
                    attr.font = .system(.body, design: .monospaced).bold()
                }
                result += attr
                break
            }
        }

        return result
    }
}

// MARK: - Console Tab Button

private struct ConsoleTabButton: View {
    let title: String
    let isSelected: Bool
    let badgeText: String?
    var accentColor: Color = CrabTimeTheme.Palette.cyan
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let badgeText {
                    Text(badgeText)
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill)
            )
            .overlay {
                Capsule()
                    .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(CrabTimeTheme.Palette.ink)
        .interactivePointer()
    }
}

// MARK: - Diagnostics Keyboard Navigation

private struct DiagnosticsKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMoveUp: onMoveUp, onMoveDown: onMoveDown, onActivate: onActivate)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onActivate = onActivate
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator: @unchecked Sendable {
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onActivate: () -> Void
        var isEnabled: Bool = true
        private var monitor: Any?

        init(onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onActivate: @escaping () -> Void) {
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
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

                // j or Arrow Down or Ctrl+N → move down
                if modifiers.isEmpty, (chars == "j" || event.keyCode == 125) {
                    MainActor.assumeIsolated { self.onMoveDown() }
                    return nil
                }
                if modifiers == .control, chars == "n" {
                    MainActor.assumeIsolated { self.onMoveDown() }
                    return nil
                }

                // k or Arrow Up or Ctrl+P → move up
                if modifiers.isEmpty, (chars == "k" || event.keyCode == 126) {
                    MainActor.assumeIsolated { self.onMoveUp() }
                    return nil
                }
                if modifiers == .control, chars == "p" {
                    MainActor.assumeIsolated { self.onMoveUp() }
                    return nil
                }

                // Enter/Return → activate
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
    }
}
