import SwiftUI

struct CodeEditorPaneView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Code Workspace")

                    Text(store.activeEditorTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)

                    Text(store.activeEditorSubtitle)
                        .font(.footnote.monospaced())
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
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
                    }

                    if store.hasSelection {
                        RunCapsuleButton(action: store.runSelectedExercise, isEnabled: store.hasSelection && !store.isRunning)
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
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)


                    if store.isEditorDirty && !store.isShowingReadonlyPreview {
                        Label("Unsaved", systemImage: "circle.fill")
                            .foregroundStyle(RustGoblinTheme.Palette.ember)
                    }

                    Spacer()

                    if !store.lastCommandDescription.isEmpty {
                        Text(store.lastCommandDescription)
                            .font(.caption.monospaced())
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                }

                Group {
                    if store.isShowingDiffPreview {
                        ReadonlyTextPreviewView(text: store.currentDiffText)
                    } else if store.isShowingReadonlyPreview {
                        if store.isShowingMarkdownPreview {
                            MarkdownDocumentView(
                                markdown: store.explorerPreviewText,
                                sourceURL: store.selectedExplorerFileURL,
                                sizingMode: .fill
                            )
                        } else {
                            ReadonlyTextPreviewView(text: store.explorerPreviewText)
                        }
                    } else {
                        CodeTextEditorView(
                            text: $store.editorText,
                            onRun: store.runSelectedExercise,
                            onSave: store.saveSelectedExercise,
                            onTest: store.runSelectedExerciseTests,
                            onCursorChange: { line in store.editorCursorLine = line }
                        )
                            .onChange(of: store.editorText) { _, _ in
                                store.handleEditorTextChange()
                            }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(RustGoblinTheme.Palette.editorBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
            } else {
                WorkspaceEmptyStateView(
                    title: "Editor Ready",
                    systemImage: "curlybraces.square",
                    description: "Import a folder or a single Rust file to turn this workspace into your active kata editor."
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
    }
}

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
                                    .foregroundStyle(selectedFileURL == tab.url ? RustGoblinTheme.Palette.ink : RustGoblinTheme.Palette.textMuted)
                                    .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                            .interactivePointer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedFileURL == tab.url ? RustGoblinTheme.Palette.selectionFill : RustGoblinTheme.Palette.buttonFill)
                        )
                        .overlay {
                            Capsule()
                                .stroke(selectedFileURL == tab.url ? RustGoblinTheme.Palette.strongDivider : RustGoblinTheme.Palette.divider, lineWidth: 1)
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
                                    RustGoblinTheme.Palette.ember,
                                    RustGoblinTheme.Palette.panelTint
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundStyle(Color.black.opacity(0.82))
                .shadow(color: RustGoblinTheme.Palette.ember.opacity(0.22), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
        .interactivePointer()
    }
}
