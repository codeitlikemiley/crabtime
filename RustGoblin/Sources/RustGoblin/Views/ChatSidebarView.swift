import AppKit
import SwiftUI

struct ChatSidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(ChatStore.self) private var chatStore
    @Environment(AISettingsStore.self) private var settingsStore
    @Environment(AIModelCatalogStore.self) private var modelCatalogStore
    @FocusState private var isComposerFocused: Bool
    @State private var selectedSlashCommandID: String?
    @State private var elapsedSeconds: Int = 0

    private let slashCommands: [ChatSlashCommand] = [
        ChatSlashCommand(
            command: "challenge",
            title: "/challenge",
            detail: "Create a new Rustlings-style challenge in the current workspace.",
            template: "/challenge "
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sessionToolbar
            transcript
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: syncKey) {
            chatStore.syncSelection(using: store)
            await modelCatalogStore.preloadIfNeeded()
        }
        .task(id: store.chatComposerFocusToken) {
            guard store.chatComposerFocusToken > 0 else {
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                isComposerFocused = true
            }
        }
        .onChange(of: chatStore.composerText) { _, _ in
            syncSlashCommandSelection()
        }
        .onChange(of: isComposerFocused) { _, _ in
            syncSlashCommandSelection()
        }
        .onChange(of: chatStore.isSending) { _, isSending in
            if isSending {
                elapsedSeconds = 0
            }
        }
        .task(id: chatStore.isSending) {
            guard chatStore.isSending else { return }
            while chatStore.isSending {
                try? await Task.sleep(for: .seconds(1))
                if chatStore.isSending { elapsedSeconds += 1 }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(text: "Learning Assistant")
            Text(store.selectedExercise?.title ?? "Exercise Chat")
                .font(.title3.weight(.bold))
                .foregroundStyle(RustGoblinTheme.Palette.ink)
            Text("Saved sessions stay attached to the current exercise, so learners can ask for help without leaving the workspace.")
                .font(.footnote)
                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
        }
    }

    private var sessionToolbar: some View {
        let provider = chatStore.selectedProvider(using: settingsStore)
        let transport = settingsStore.preference(for: provider).transport

        return VStack(alignment: .leading, spacing: 10) {
            if let banner = store.aiRuntimeBannerMessage(for: provider, transport: transport) {
                Button {
                    store.showAIRuntime()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: transport == .acp ? "bolt.horizontal.circle.fill" : "info.circle")
                            .foregroundStyle(transport == .acp ? RustGoblinTheme.Palette.cyan : RustGoblinTheme.Palette.textMuted)
                        Text(banner)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius)
                            .fill(RustGoblinTheme.Palette.buttonFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius)
                            .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }

            HStack(spacing: 8) {
                Menu {
                    Picker("Provider", selection: Binding(
                        get: { chatStore.selectedProvider(using: settingsStore) },
                        set: { chatStore.updateSelectedProvider($0, using: store, settingsStore: settingsStore) }
                    )) {
                        ForEach(AIProviderKind.defaultChatProviders) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                } label: {
                    let provider = chatStore.selectedProvider(using: settingsStore)
                    Label(provider.shortTitle, systemImage: provider.systemImage)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
                        .overlay {
                            Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                        }
                }
                .menuStyle(.borderlessButton)
                .interactivePointer()

                ModelComboBox(
                    text: Binding(
                        get: { chatStore.selectedModel(using: settingsStore) },
                        set: { chatStore.updateSelectedModel($0, using: store, settingsStore: settingsStore) }
                    ),
                    items: modelCatalogStore.models(
                        for: chatStore.selectedProvider(using: settingsStore),
                        selectedModel: chatStore.selectedModel(using: settingsStore)
                    ),
                    placeholder: chatStore.selectedProvider(using: settingsStore).defaultModel
                ) { value in
                    chatStore.updateSelectedModel(value, using: store, settingsStore: settingsStore)
                }
                .frame(height: 28)

                if chatStore.selectedProvider(using: settingsStore) == .openCodeCLI {
                    Button {
                        Task {
                            await modelCatalogStore.refreshModels(for: .openCodeCLI)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .interactivePointer()
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(RustGoblinTheme.Palette.buttonFill))
                        .overlay {
                            Circle().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }

            HStack(spacing: 8) {
                Menu {
                    if chatStore.sessions.isEmpty {
                        Text("No saved sessions yet")
                    } else {
                        ForEach(chatStore.sessions) { session in
                            Button {
                                chatStore.selectSession(session.id, using: store)
                            } label: {
                                Label(session.title, systemImage: session.providerKind.systemImage)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(chatStore.selectedSession?.title ?? "No Session")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RustGoblinTheme.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
                    .overlay {
                        Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                    }
                }
                .menuStyle(.borderlessButton)
                .interactivePointer()

                Button("New Session") {
                    chatStore.createSession(using: store)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(RustGoblinTheme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
                .overlay {
                    Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
                .interactivePointer()
                .disabled(chatStore.isSending)

                Button("Clear") {
                    chatStore.clearCurrentSession(using: store)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
                .overlay {
                    Capsule().stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
                .interactivePointer()
                .disabled(chatStore.selectedSession == nil || chatStore.isSending)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            List {
                if chatStore.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No messages yet")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                        Text("Ask about the selected exercise, compiler errors, test failures, or the current source buffer.")
                            .font(.footnote)
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(chatStore.messages) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .onChange(of: chatStore.messages.count) {
                guard let lastID = chatStore.messages.last?.id else {
                    return
                }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .fill(RustGoblinTheme.Palette.subtleFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = chatStore.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if isShowingSlashCommandMenu {
                slashCommandMenu
            }

            TextField(
                "Ask for help with the current exercise…",
                text: Binding(
                    get: { chatStore.composerText },
                    set: { chatStore.composerText = $0 }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(3...7)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    .fill(RustGoblinTheme.Palette.raisedFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
            }
            .foregroundStyle(RustGoblinTheme.Palette.ink)
            .focused($isComposerFocused)
            .disabled(chatStore.isSending)
            .onSubmit {
                handleComposerSubmit()
            }
            .background(
                ChatComposerKeyBridge(
                    isEnabled: isComposerFocused,
                    isShowingSlashCommandMenu: isShowingSlashCommandMenu,
                    onMoveUp: moveSlashCommandSelectionUp,
                    onMoveDown: moveSlashCommandSelectionDown,
                    onAcceptSlashCommand: acceptSelectedSlashCommand,
                    onSubmit: handleComposerSubmit
                )
            )

            HStack {
                Text("Context: current exercise, .rs, .md, Cargo.toml, current buffer, and latest run output.")
                    .font(.caption)
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)

                Spacer()

                Button {
                    handleComposerSubmit()
                } label: {
                    HStack(spacing: 8) {
                        if chatStore.isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(RustGoblinTheme.Palette.ink)
                            Text(elapsedSeconds > 0 ? "\(elapsedSeconds)s…" : "Generating…")
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Send")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RustGoblinTheme.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(RustGoblinTheme.Palette.selectionFill))
                    .overlay {
                        Capsule().stroke(RustGoblinTheme.Palette.strongDivider, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .interactivePointer()
                .disabled(chatStore.isSending)
            }
        }
    }

    private var syncKey: String {
        [
            store.selectedWorkspaceRootPath ?? "workspace-none",
            store.selectedExercise?.sourceURL.standardizedFileURL.path ?? "exercise-none"
        ].joined(separator: "::")
    }

    private var currentSlashQuery: String? {
        let text = chatStore.composerText
        guard text.hasPrefix("/") else {
            return nil
        }

        let token = text.split(maxSplits: 1, whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard token.hasPrefix("/") else {
            return nil
        }

        if text.contains(where: \.isWhitespace) {
            return nil
        }

        return String(token.dropFirst())
    }

    private var filteredSlashCommands: [ChatSlashCommand] {
        guard let query = currentSlashQuery else {
            return []
        }

        if query.isEmpty {
            return slashCommands
        }

        return slashCommands.filter { command in
            command.command.localizedCaseInsensitiveContains(query) ||
            command.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var isShowingSlashCommandMenu: Bool {
        isComposerFocused && currentSlashQuery != nil && !filteredSlashCommands.isEmpty
    }

    private var selectedSlashCommand: ChatSlashCommand? {
        if let selectedSlashCommandID {
            return filteredSlashCommands.first(where: { $0.id == selectedSlashCommandID })
        }
        return filteredSlashCommands.first
    }

    private var slashCommandMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(filteredSlashCommands) { command in
                Button {
                    applySlashCommand(command)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSlashCommandSelected(command) ? RustGoblinTheme.Palette.panelTint : RustGoblinTheme.Palette.textMuted)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(command.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RustGoblinTheme.Palette.ink)

                            Text(command.detail)
                                .font(.caption)
                                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSlashCommandSelected(command) ? RustGoblinTheme.Palette.selectionFill : RustGoblinTheme.Palette.buttonFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSlashCommandSelected(command) ? RustGoblinTheme.Palette.strongDivider : RustGoblinTheme.Palette.divider, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .fill(RustGoblinTheme.Palette.panelFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(RustGoblinTheme.Palette.strongDivider, lineWidth: 1)
        }
    }

    private func syncSlashCommandSelection() {
        guard isShowingSlashCommandMenu else {
            selectedSlashCommandID = nil
            return
        }

        if let selectedSlashCommandID,
           filteredSlashCommands.contains(where: { $0.id == selectedSlashCommandID }) {
            return
        }

        selectedSlashCommandID = filteredSlashCommands.first?.id
    }

    private func moveSlashCommandSelectionUp() {
        guard !filteredSlashCommands.isEmpty else {
            return
        }

        let currentIndex = filteredSlashCommands.firstIndex(where: { $0.id == selectedSlashCommandID }) ?? 0
        let nextIndex = currentIndex == 0 ? filteredSlashCommands.count - 1 : currentIndex - 1
        selectedSlashCommandID = filteredSlashCommands[nextIndex].id
    }

    private func moveSlashCommandSelectionDown() {
        guard !filteredSlashCommands.isEmpty else {
            return
        }

        let currentIndex = filteredSlashCommands.firstIndex(where: { $0.id == selectedSlashCommandID }) ?? -1
        let nextIndex = (currentIndex + 1) % filteredSlashCommands.count
        selectedSlashCommandID = filteredSlashCommands[nextIndex].id
    }

    @discardableResult
    private func acceptSelectedSlashCommand() -> Bool {
        guard let selectedSlashCommand else {
            return false
        }

        applySlashCommand(selectedSlashCommand)
        return true
    }

    private func isSlashCommandSelected(_ command: ChatSlashCommand) -> Bool {
        command.id == selectedSlashCommandID
    }

    private func applySlashCommand(_ command: ChatSlashCommand) {
        chatStore.composerText = command.template
        selectedSlashCommandID = command.id
        isComposerFocused = true
    }

    private func handleComposerSubmit() {
        if isShowingSlashCommandMenu, acceptSelectedSlashCommand() {
            return
        }

        chatStore.sendCurrentMessage(using: store)
    }
}

private struct ChatSlashCommand: Identifiable {
    let command: String
    let title: String
    let detail: String
    let template: String

    var id: String { command }
}

private struct ChatComposerKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let isShowingSlashCommandMenu: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAcceptSlashCommand: () -> Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            isShowingSlashCommandMenu: isShowingSlashCommandMenu,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onAcceptSlashCommand: onAcceptSlashCommand,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isShowingSlashCommandMenu = isShowingSlashCommandMenu
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onAcceptSlashCommand = onAcceptSlashCommand
        context.coordinator.onSubmit = onSubmit
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        var isEnabled: Bool
        var isShowingSlashCommandMenu: Bool
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onAcceptSlashCommand: () -> Bool
        var onSubmit: () -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(
            isEnabled: Bool,
            isShowingSlashCommandMenu: Bool,
            onMoveUp: @escaping () -> Void,
            onMoveDown: @escaping () -> Void,
            onAcceptSlashCommand: @escaping () -> Bool,
            onSubmit: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.isShowingSlashCommandMenu = isShowingSlashCommandMenu
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onAcceptSlashCommand = onAcceptSlashCommand
            self.onSubmit = onSubmit
        }

        func attach(to view: NSView) {
            hostView = view
            if monitor == nil {
                startMonitoring()
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }

                guard self.isEnabled, self.hostView?.window?.isKeyWindow == true else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let characters = event.charactersIgnoringModifiers?.lowercased()

                if self.isShowingSlashCommandMenu {
                    if modifiers.isEmpty, event.keyCode == 125 {
                        self.onMoveDown()
                        return nil
                    }

                    if modifiers.isEmpty, event.keyCode == 126 {
                        self.onMoveUp()
                        return nil
                    }

                    if modifiers == .control, characters == "n" {
                        self.onMoveDown()
                        return nil
                    }

                    if modifiers == .control, characters == "p" {
                        self.onMoveUp()
                        return nil
                    }

                    if modifiers.isEmpty, [36, 76].contains(event.keyCode), self.onAcceptSlashCommand() {
                        return nil
                    }
                } else if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                    self.onSubmit()
                    return nil
                }

                return event
            }
        }
    }
}

private struct ChatMessageBubble: View {
    @Environment(ChatStore.self) private var chatStore
    let message: ExerciseChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(roleTitle, systemImage: roleIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleTint)
                Spacer()
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)

                Button {
                    chatStore.deleteMessage(message.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }

            if message.role == .assistant {
                AssistantMarkdownText(markdown: message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(RustGoblinTheme.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
        }
        .contextMenu {
            Button("Delete Message", role: .destructive) {
                chatStore.deleteMessage(message.id)
            }
        }
    }

    private var roleTitle: String {
        switch message.role {
        case .assistant:
            "Tutor"
        case .user:
            "You"
        case .system:
            "System"
        case .error:
            "Error"
        }
    }

    private var roleIcon: String {
        switch message.role {
        case .assistant:
            "sparkles"
        case .user:
            "person.fill"
        case .system:
            "gearshape.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    private var roleTint: Color {
        switch message.role {
        case .assistant:
            RustGoblinTheme.Palette.cyan
        case .user:
            RustGoblinTheme.Palette.panelTint
        case .system:
            RustGoblinTheme.Palette.textMuted
        case .error:
            .red
        }
    }

    private var backgroundFill: Color {
        switch message.role {
        case .assistant:
            RustGoblinTheme.Palette.raisedFill
        case .user:
            RustGoblinTheme.Palette.selectionFill
        case .system:
            RustGoblinTheme.Palette.buttonFill
        case .error:
            Color.red.opacity(0.12)
        }
    }
}

private struct AssistantMarkdownText: View {
    let markdown: String

    var body: some View {
        Group {
            if let rendered = renderedMarkdown {
                Text(rendered)
                    .font(.body)
                    .foregroundStyle(RustGoblinTheme.Palette.ink)
            } else {
                Text(markdown)
                    .font(.body)
                    .foregroundStyle(RustGoblinTheme.Palette.ink)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderedMarkdown: AttributedString? {
        try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
    }
}
