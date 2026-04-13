import SwiftUI

struct CodeEditorPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(ProcessStore.self) private var processStore

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Code Workspace")

                    Text(store.activeEditorTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)

                    Text(store.activeEditorSubtitle)
                        .font(.footnote.monospaced())
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                }

                Spacer()

                HStack(spacing: 8) {
                    if store.canToggleDiffMode {
                        IconGlassButton(
                            systemImage: store.isShowingDiffPreview ? "doc.text" : "arrow.left.arrow.right.square",
                            helpText: store.isShowingDiffPreview ? "Return to editor" : "Show diff",
                            isActive: store.isShowingDiffPreview,
                            action: store.toggleDiffMode
                        )
                    }

                    if store.canResetActiveDocument {
                        IconGlassButton(
                            systemImage: "arrow.counterclockwise",
                            helpText: "Restore file",
                            action: store.resetSelectedExercise
                        )
                        .disabled(store.isCurrentExerciseEnriching)
                        .opacity(store.isCurrentExerciseEnriching ? 0.4 : 1)
                    }

                    if store.hasSelection {
                        RunCapsuleButton(
                            action: { store.runSelectedExercise(processStore: processStore) },
                            isEnabled: store.hasSelection && !store.isRunning && !store.isCurrentExerciseEnriching
                        )
                    }

                    IconGlassButton(
                        systemImage: "terminal",
                        helpText: store.showsTerminal ? "Hide terminal" : "Show terminal",
                        isActive: store.showsTerminal,
                        action: store.toggleTerminalVisibility
                    )

                    IconGlassButton(
                        systemImage: store.contentDisplayMode == .editorMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        helpText: store.contentDisplayMode == .editorMaximized ? "Return to split view" : "Maximize editor",
                        isActive: store.contentDisplayMode == .editorMaximized,
                        action: store.toggleEditorMaximize
                    )

                    IconGlassButton(
                        systemImage: "sidebar.right",
                        helpText: store.isInspectorVisible ? "Hide inspector" : "Show inspector",
                        isActive: store.isInspectorVisible,
                        action: store.toggleInspector
                    )
                }
            }

            if store.hasSelection || store.isShowingExplorerPreview {
                OpenFileTabsView()

                HStack {
                    Text("\(store.activeEditorLineCount) lines")
                        .font(.caption)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                    if store.isEditorDirty && !store.isShowingReadonlyPreview {
                        Label("Unsaved", systemImage: "circle.fill")
                            .foregroundStyle(CrabTimeTheme.Palette.ember)
                    }

                    Spacer()

                    if !processStore.lastCommandDescription.isEmpty {
                        Text(processStore.lastCommandDescription)
                            .font(.caption.monospaced())
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    }
                }

                // ── AI Enrichment Banner ──────────────────────────────────────
                if store.isCurrentExerciseEnriching {
                    EnrichmentBanner()
                }

                Group {
                    if store.isCurrentExerciseEnriching {
                        // Read-only while AI is rewriting the file — prevents race conditions
                        ReadonlyTextPreviewView(
                            text: store.editorText,
                            fileExtension: currentFileExtension,
                            showLineNumbers: store.showLineNumbers
                        )
                    } else if store.isShowingDiffPreview {
                        ReadonlyTextPreviewView(
                            text: store.currentDiffText,
                            showLineNumbers: store.showLineNumbers
                        )
                    } else if store.isShowingReadonlyPreview {
                        if store.isShowingMarkdownPreview {
                            MarkdownDocumentView(
                                markdown: store.explorerPreviewText,
                                sourceURL: store.selectedExplorerFileURL,
                                sizingMode: .fill
                            )
                        } else {
                            ReadonlyTextPreviewView(
                                text: store.explorerPreviewText,
                                fileExtension: currentFileExtension,
                                showLineNumbers: store.showLineNumbers
                            )
                        }
                    } else {
                        CodeTextEditorView(
                            text: $store.editorText,
                            onRun: { store.runSelectedExercise(processStore: processStore) },
                            onSave: store.saveSelectedExercise,
                            onTest: { store.runSelectedExerciseTests(processStore: processStore) },
                            onCursorChange: { line in store.editorCursorLine = line },
                            onCursorOffsetChange: { offset in store.editorCursorOffset = offset },
                            onSaveCursorPosition: { offset, path in
                                store.setCursorPosition(offset: offset, forPath: path)
                            },
                            showLineNumbers: store.showLineNumbers,
                            goToLine: store.goToLineTarget
                        )
                            .onChange(of: store.editorText) { _, _ in
                                store.handleEditorTextChange()
                            }
                            .onChange(of: store.goToLineToken) { _, _ in
                                // Use a short delay to let the view settle after palette dismiss
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    guard let line = store.goToLineTarget, line > 0 else { return }
                                    store.goToLineTarget = nil
                                    // Post a notification so the text view can handle it
                                    NotificationCenter.default.post(
                                        name: .goToLineRequested,
                                        object: nil,
                                        userInfo: ["line": line]
                                    )
                                }
                            }
                            .onChange(of: store.restoreCursorToken) { _, _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if let offset = store.restoreCursorOffset {
                                        NotificationCenter.default.post(
                                            name: .restoreCursorPositionRequested,
                                            object: nil,
                                            userInfo: ["offset": offset]
                                        )
                                    } else {
                                        // New file, focus editor at current position
                                        NotificationCenter.default.post(
                                            name: .focusTextEditorRequested,
                                            object: nil
                                        )
                                    }
                                }
                            }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CrabTimeTheme.Palette.editorBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            store.isCurrentExerciseEnriching
                                ? CrabTimeTheme.Palette.ember.opacity(0.5)
                                : CrabTimeTheme.Palette.divider,
                            lineWidth: store.isCurrentExerciseEnriching ? 1.5 : 1
                        )
                }
            } else {
                WorkspaceEmptyStateView(
                    title: "Editor Ready",
                    systemImage: "curlybraces.square",
                    description: "Import a folder or a Rust file to turn this workspace into your active kata editor."
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
        .overlay {
            if store.isCommandPalettePresented {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture {
                        store.hideCommandPalette()
                    }
                    .overlay(alignment: .top) {
                        CommandPaletteView()
                            .padding(.top, 40)
                    }
            }
        }
    }

    private var currentFileExtension: String? {
        store.selectedExplorerFileURL?.pathExtension
    }
}

// MARK: - Enrichment Banner

private struct EnrichmentBanner: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.mini)
                .tint(CrabTimeTheme.Palette.ember)

            Text("AI is enriching this file — editing is disabled until complete.")
                .font(.caption.weight(.medium))
                .foregroundStyle(CrabTimeTheme.Palette.ember)

            Spacer()

            Text("Read-only")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CrabTimeTheme.Palette.ember.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(CrabTimeTheme.Palette.ember.opacity(0.12)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CrabTimeTheme.Palette.ember.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CrabTimeTheme.Palette.ember.opacity(0.25), lineWidth: 1)
        }
        .opacity(isAnimating ? 1 : 0.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Open File Tabs

private struct OpenFileTabsView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        if !store.currentOpenTabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.currentOpenTabs) { tab in
                        HStack(spacing: 6) {
                            Button {
                                store.activateTab(tab)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: tabIcon(for: tab.url))
                                        .font(.system(size: 11, weight: .semibold))

                                    Text(tab.title)
                                        .lineLimit(1)

                                    // Spinner on tabs whose file is being enriched
                                    if store.isEnriching(exerciseURL: tab.url) {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .tint(CrabTimeTheme.Palette.ember)
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.plain)
                            .interactivePointer()

                            Button {
                                store.closeTab(tab)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(selectedFileURL == tab.url ? CrabTimeTheme.Palette.ink : CrabTimeTheme.Palette.textMuted)
                                    .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                            .interactivePointer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedFileURL == tab.url ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill)
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    store.isEnriching(exerciseURL: tab.url)
                                        ? CrabTimeTheme.Palette.ember.opacity(0.6)
                                        : (selectedFileURL == tab.url ? CrabTimeTheme.Palette.strongDivider : CrabTimeTheme.Palette.divider),
                                    lineWidth: 1
                                )
                        }
                    }
                }
            }
        }
    }

    private var selectedFileURL: URL? {
        store.selectedExplorerFileURL ?? store.selectedExercise?.sourceURL
    }

    private func tabIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "rs":
            "curlybraces"
        case "md":
            "doc.text"
        case "toml":
            "shippingbox"
        default:
            "doc"
        }
    }
}

// MARK: - Run Button

private struct RunCapsuleButton: View {
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    CrabTimeTheme.Palette.ember,
                                    CrabTimeTheme.Palette.panelTint
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundStyle(Color.black.opacity(0.82))
                .shadow(color: CrabTimeTheme.Palette.ember.opacity(0.22), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
        .interactivePointer()
    }
}
