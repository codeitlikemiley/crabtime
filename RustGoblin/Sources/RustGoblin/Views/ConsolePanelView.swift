import SwiftUI

struct ConsolePanelView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Terminal Output", tint: RustGoblinTheme.Palette.textMuted)
                    Text("Feedback Loop")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                }

                Spacer()

                HStack(spacing: 8) {
                    if store.errorCount > 0 {
                        TerminalStatPill(text: "\(store.errorCount) Error", tint: .red)
                    }

                    if store.warningCount > 0 {
                        TerminalStatPill(text: "\(store.warningCount) Warning", tint: RustGoblinTheme.Palette.panelTint)
                    }
                }

                HStack(spacing: 8) {
                    ConsoleTabButton(
                        title: "Output",
                        isSelected: store.selectedConsoleTab == .output,
                        badgeText: nil
                    ) {
                        store.selectedConsoleTab = .output
                    }

                    ConsoleTabButton(
                        title: "Diagnostics",
                        isSelected: store.selectedConsoleTab == .diagnostics,
                        badgeText: store.diagnosticsCount == 0 ? nil : "\(store.diagnosticsCount)",
                        accentColor: store.errorCount > 0 ? .red : RustGoblinTheme.Palette.ember
                    ) {
                        store.selectedConsoleTab = .diagnostics
                    }

                    ConsoleTabButton(
                        title: "Session",
                        isSelected: store.selectedConsoleTab == .session,
                        badgeText: nil
                    ) {
                        store.selectedConsoleTab = .session
                    }
                }
            }

            Group {
                switch store.selectedConsoleTab {
                case .output:
                    ScrollView {
                        Text(store.consoleOutput.isEmpty ? "Output appears here." : store.consoleOutput)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                case .diagnostics:
                    if store.diagnostics.isEmpty {
                        WorkspaceEmptyStateView(
                            title: "No Diagnostics",
                            systemImage: "checkmark.circle",
                            description: "Compiler warnings and errors appear here after a run."
                        )
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(store.diagnostics) { diagnostic in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label(
                                            diagnostic.severity == .error ? "Error" : "Warning",
                                            systemImage: diagnostic.severity == .error
                                                ? "xmark.octagon.fill"
                                                : "exclamationmark.triangle.fill"
                                        )
                                        .foregroundStyle(diagnostic.severity == .error ? .red : RustGoblinTheme.Palette.ember)

                                        Text(diagnostic.message)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundStyle(RustGoblinTheme.Palette.ink)

                                        if let line = diagnostic.line {
                                            Text("Line \(line)")
                                                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius)
                                            .fill(RustGoblinTheme.Palette.subtleFill)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius)
                                            .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                                    }
                                }
                            }
                        }
                    }
                case .session:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.sessionLog, id: \.self) { entry in
                                Text(entry)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(RustGoblinTheme.Palette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    .fill(RustGoblinTheme.Palette.terminalFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
    }
}

private struct TerminalStatPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
            .foregroundStyle(tint)
    }
}

private struct ConsoleTabButton: View {
    let title: String
    let isSelected: Bool
    let badgeText: String?
    var accentColor: Color = RustGoblinTheme.Palette.cyan
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
                    .fill(isSelected ? RustGoblinTheme.Palette.selectionFill : RustGoblinTheme.Palette.buttonFill)
            )
            .overlay {
                Capsule()
                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(RustGoblinTheme.Palette.ink)
        .interactivePointer()
    }
}
