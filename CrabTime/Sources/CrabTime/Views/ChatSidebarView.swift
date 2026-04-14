import AppKit
import SwiftUI

struct ChatSidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Environment(ProcessStore.self) private var processStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(AISettingsStore.self) private var settingsStore
    @Environment(AIModelCatalogStore.self) private var modelCatalogStore
    @FocusState private var isComposerFocused: Bool
    @State private var menuState: ComposerMenuState = .none
    @State private var selectedSlashCommandID: String?
    @State private var selectedFileNodeID: URL?
    @State private var selectedLogTokenID: String?
    @State private var elapsedSeconds: Int = 0

    private let slashCommands: [ChatSlashCommand] = [
        ChatSlashCommand(
            command: "challenge",
            title: "/challenge",
            detail: "Create a new Rustlings-style challenge in the current workspace.",
            template: "/challenge "
        ),
        ChatSlashCommand(
            command: "verify",
            title: "/verify",
            detail: "Run the tests for the selected exercise and verify your solution.",
            template: "/verify"
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
            syncMenuState()
        }
        .onChange(of: isComposerFocused) { _, _ in
            syncMenuState()
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
            Text(chatTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(CrabTimeTheme.Palette.ink)
            Text(chatDescription)
                .font(.footnote)
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
        }
    }

    private var sessionToolbar: some View {
        let provider = chatStore.selectedProvider(using: settingsStore)
        let transport = settingsStore.preference(for: provider).transport

        return VStack(alignment: .leading, spacing: 10) {
            if let banner = processStore.aiRuntimeBannerMessage(for: provider, transport: transport) {
                Button {
                    processStore.showAIRuntime(using: navigationStore)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: transport == .acp ? "bolt.horizontal.circle.fill" : "info.circle")
                            .foregroundStyle(transport == .acp ? CrabTimeTheme.Palette.cyan : CrabTimeTheme.Palette.textMuted)
                        Text(banner)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CrabTimeTheme.Palette.ink)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                            .fill(CrabTimeTheme.Palette.buttonFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius)
                            .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
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
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                        .overlay {
                            Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
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
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .interactivePointer()
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(CrabTimeTheme.Palette.buttonFill))
                        .overlay {
                            Circle().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
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
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                    .overlay {
                        Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                    }
                }
                .menuStyle(.borderlessButton)
                .interactivePointer()

                Button("New Session") {
                    chatStore.createSession(using: store)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                .overlay {
                    Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
                .interactivePointer()
                .disabled(chatStore.isSending)

                Button("Clear") {
                    chatStore.clearCurrentSession(using: store)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                .overlay {
                    Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
                .interactivePointer()
                .disabled(chatStore.selectedSession == nil || chatStore.isSending)
            }
        }
    }

    private var scrollAnchorID: String { "__chat_bottom_anchor__" }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chatStore.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No messages yet")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(CrabTimeTheme.Palette.ink)
                            Text(emptyStateDescription)
                                .font(.footnote)
                                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    } else {
                        ForEach(chatStore.messages) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(scrollAnchorID)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatStore.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatStore.messages.last?.content) {
                scrollToBottom(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .fill(CrabTimeTheme.Palette.subtleFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Slight delay lets the List layout the new row before we scroll
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(scrollAnchorID, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = chatStore.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if menuState != .none {
                activeMenu
            }

            TextField(
                composerPlaceholder,
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
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                    .fill(CrabTimeTheme.Palette.raisedFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                    .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
            .foregroundStyle(CrabTimeTheme.Palette.ink)
            .focused($isComposerFocused)
            .disabled(chatStore.isSending)
            .onSubmit {
                handleComposerSubmit()
            }
            .background(
                ChatComposerKeyBridge(
                    isEnabled: isComposerFocused,
                    isShowingMenu: menuState != .none,
                    onMoveUp: moveSelectionUp,
                    onMoveDown: moveSelectionDown,
                    onAcceptMenu: acceptSelectedMenu,
                    onSubmit: handleComposerSubmit
                )
            )

            HStack {
                Text(contextDescription)
                    .font(.caption)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                Spacer()

                Button {
                    handleComposerSubmit()
                } label: {
                    HStack(spacing: 8) {
                        if chatStore.isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(CrabTimeTheme.Palette.ink)
                            Text(elapsedSeconds > 0 ? "\(elapsedSeconds)s…" : "Generating…")
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Send")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(CrabTimeTheme.Palette.selectionFill))
                    .overlay {
                        Capsule().stroke(CrabTimeTheme.Palette.strongDivider, lineWidth: 1)
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
            store.selectedExercise?.chatScopeURL.standardizedFileURL.path ?? "exercise-none"
        ].joined(separator: "::")
    }

    private var chatTitle: String {
        if let exercise = store.selectedExercise {
            return exercise.title
        }
        if let workspace = store.workspace {
            return "\(workspace.title) Chat"
        }
        return "General Chat"
    }

    private var chatDescription: String {
        "Exercise context is included when one is selected. Otherwise, chat stays available with whatever workspace context exists."
    }

    private var emptyStateDescription: String {
        if store.selectedExercise != nil {
            return "Ask about the selected exercise, compiler errors, test failures, or the current source buffer."
        }
        if store.workspace != nil {
            return "Ask about this workspace, the active file, compiler errors, or general Rust questions."
        }
        return "Ask a general Rust or programming question. Workspace context will appear here when you load one."
    }

    private var composerPlaceholder: String {
        if store.selectedExercise != nil {
            return "Ask for help with the current exercise…"
        }
        if store.workspace != nil {
            return "Ask about this workspace or Rust…"
        }
        return "Ask anything about Rust…"
    }


    private var contextDescription: String {
        let text = chatStore.composerText
        let tokens = store.workspace.map { ChatContextTokenParser.parse(text, workspaceRoot: $0.rootURL) } ?? []
        
        if tokens.isEmpty {
            if store.selectedExercise != nil {
                return "Context: exercise files, current buffer, and output."
            }
            if store.workspace != nil {
                return "Context: workspace files, current buffer, and output."
            }
            return "Context: general chat until you load a workspace."
        }
        
        let fileTokens = tokens.compactMap { token -> String? in
            if case .file(let url) = token { return "@\(url.lastPathComponent)" }
            return nil
        }
        
        var descs: [String] = []
        if !fileTokens.isEmpty {
            if fileTokens.count == 1 {
                descs.append("\(fileTokens[0])")
            } else {
                descs.append("\(fileTokens[0]) + \(fileTokens.count - 1) more")
            }
        }
        if tokens.contains(.output) { descs.append("#output") }
        if tokens.contains(.diagnostics) { descs.append("#diagnostics") }
        
        return "Context: " + descs.joined(separator: ", ")
    }

    // --- Menu State Management ---

    private func syncMenuState() {
        guard isComposerFocused else {
            menuState = .none
            return
        }

        let text = chatStore.composerText
        guard !text.hasSuffix(" ") else {
            menuState = .none
            return
        }

        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard let lastWord = words.last.map(String.init), !lastWord.isEmpty else {
            menuState = .none
            return
        }

        if text.hasPrefix("/") && words.count == 1 {
            let query = String(lastWord.dropFirst())
            menuState = .slash(query)
            if selectedSlashCommandID == nil || !filteredSlashCommands(query).contains(where: { $0.id == selectedSlashCommandID }) {
                selectedSlashCommandID = filteredSlashCommands(query).first?.id
            }
            return
        }

        if lastWord.hasPrefix("@") {
            let query = String(lastWord.dropFirst())
            menuState = .filePicker(query)
            if selectedFileNodeID == nil || !filteredWorkspaceFiles(query).contains(where: { $0.id == selectedFileNodeID }) {
                selectedFileNodeID = filteredWorkspaceFiles(query).first?.id
            }
            return
        }

        if lastWord.hasPrefix("#") {
            let query = String(lastWord.dropFirst())
            menuState = .logPicker(query)
            if selectedLogTokenID == nil || !filteredLogTokens(query).contains(where: { $0.token == selectedLogTokenID }) {
                selectedLogTokenID = filteredLogTokens(query).first?.token
            }
            return
        }

        menuState = .none
    }

    private func filteredSlashCommands(_ query: String) -> [ChatSlashCommand] {
        if query.isEmpty { return slashCommands }
        return slashCommands.filter {
            $0.command.localizedCaseInsensitiveContains(query) ||
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func filteredWorkspaceFiles(_ query: String) -> [WorkspaceFileNode] {
        let all = store.allWorkspaceFiles
        if query.isEmpty { return Array(all.prefix(8)) }
        return Array(all.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.url.path.localizedCaseInsensitiveContains(query)
        }.prefix(8))
    }

    private func filteredLogTokens(_ query: String) -> [ChatLogToken] {
        if query.isEmpty { return standardLogTokens }
        return standardLogTokens.filter {
            $0.token.localizedCaseInsensitiveContains(query)
        }
    }

    // --- Menus UI ---

    @ViewBuilder
    private var activeMenu: some View {
        switch menuState {
        case .slash(let query):
            slashCommandMenu(query: query)
        case .filePicker(let query):
            filePickerMenu(query: query)
        case .logPicker(let query):
            logPickerMenu(query: query)
        case .none:
            EmptyView()
        }
    }

    private func slashCommandMenu(query: String) -> some View {
        let commands = filteredSlashCommands(query)
        guard !commands.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(commands) { command in
                    let isSelected = command.id == selectedSlashCommandID
                    Button {
                        applySlashCommand(command)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? CrabTimeTheme.Palette.panelTint : CrabTimeTheme.Palette.textMuted)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                                Text(command.detail)
                                    .font(.caption)
                                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? CrabTimeTheme.Palette.strongDivider : CrabTimeTheme.Palette.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius).fill(CrabTimeTheme.Palette.panelFill))
            .overlay(RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius).stroke(CrabTimeTheme.Palette.strongDivider, lineWidth: 1))
        )
    }

    private func filePickerMenu(query: String) -> some View {
        let files = filteredWorkspaceFiles(query)
        guard !files.isEmpty else { return AnyView(EmptyView()) }
        
        let rootPath = store.workspace?.rootURL.standardizedFileURL.path ?? ""

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(files) { file in
                    let isSelected = file.id == selectedFileNodeID
                    let filePath = file.url.standardizedFileURL.path
                    let relPath = filePath.hasPrefix(rootPath + "/") ? String(filePath.dropFirst(rootPath.count + 1)) : file.name

                    Button {
                        applyFileToken(file, query: query)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CrabTimeTheme.Palette.ink)
                            Text(relPath)
                                .font(.system(size: 10))
                                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? CrabTimeTheme.Palette.strongDivider : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius).fill(CrabTimeTheme.Palette.panelFill))
            .overlay(RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius).stroke(CrabTimeTheme.Palette.strongDivider, lineWidth: 1))
        )
    }

    private func logPickerMenu(query: String) -> some View {
        let tokens = filteredLogTokens(query)
        guard !tokens.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tokens) { token in
                    let isSelected = token.token == selectedLogTokenID
                    Button {
                        applyLogToken(token, query: query)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.token)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CrabTimeTheme.Palette.ink)
                            Text(token.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? CrabTimeTheme.Palette.strongDivider : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius).fill(CrabTimeTheme.Palette.panelFill))
            .overlay(RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius).stroke(CrabTimeTheme.Palette.strongDivider, lineWidth: 1))
        )
    }

    // --- Navigation ---

    private func moveSelectionUp() {
        switch menuState {
        case .slash(let query):
            let items = filteredSlashCommands(query)
            guard !items.isEmpty else { return }
            let idx = items.firstIndex(where: { $0.id == selectedSlashCommandID }) ?? 0
            selectedSlashCommandID = items[idx == 0 ? items.count - 1 : idx - 1].id
        case .filePicker(let query):
            let items = filteredWorkspaceFiles(query)
            guard !items.isEmpty else { return }
            let idx = items.firstIndex(where: { $0.id == selectedFileNodeID }) ?? 0
            selectedFileNodeID = items[idx == 0 ? items.count - 1 : idx - 1].id
        case .logPicker(let query):
            let items = filteredLogTokens(query)
            guard !items.isEmpty else { return }
            let idx = items.firstIndex(where: { $0.token == selectedLogTokenID }) ?? 0
            selectedLogTokenID = items[idx == 0 ? items.count - 1 : idx - 1].token
        case .none:
            break
        }
    }

    private func moveSelectionDown() {
        switch menuState {
        case .slash(let query):
            let items = filteredSlashCommands(query)
            guard !items.isEmpty else { return }
            let idx = items.firstIndex(where: { $0.id == selectedSlashCommandID }) ?? -1
            selectedSlashCommandID = items[(idx + 1) % items.count].id
        case .filePicker(let query):
            let items = filteredWorkspaceFiles(query)
            guard !items.isEmpty else { return }
            let idx = items.firstIndex(where: { $0.id == selectedFileNodeID }) ?? -1
            selectedFileNodeID = items[(idx + 1) % items.count].id
        case .logPicker(let query):
            let items = filteredLogTokens(query)
            guard !items.isEmpty else { return }
            let idx = items.firstIndex(where: { $0.token == selectedLogTokenID }) ?? -1
            selectedLogTokenID = items[(idx + 1) % items.count].token
        case .none:
            break
        }
    }

    @discardableResult
    private func acceptSelectedMenu() -> Bool {
        switch menuState {
        case .slash(let query):
            if let cmd = filteredSlashCommands(query).first(where: { $0.id == selectedSlashCommandID }) {
                applySlashCommand(cmd)
                return true
            }
        case .filePicker(let query):
            if let file = filteredWorkspaceFiles(query).first(where: { $0.id == selectedFileNodeID }) {
                applyFileToken(file, query: query)
                return true
            }
        case .logPicker(let query):
            if let tkn = filteredLogTokens(query).first(where: { $0.token == selectedLogTokenID }) {
                applyLogToken(tkn, query: query)
                return true
            }
        case .none:
            break
        }
        return false
    }

    private func applySlashCommand(_ command: ChatSlashCommand) {
        chatStore.composerText = command.template
        selectedSlashCommandID = command.id
        isComposerFocused = true
    }

    private func applyFileToken(_ node: WorkspaceFileNode, query: String) {
        let rootPath = store.workspace?.rootURL.standardizedFileURL.path ?? ""
        let filePath = node.url.standardizedFileURL.path
        let relPath = filePath.hasPrefix(rootPath + "/") ? String(filePath.dropFirst(rootPath.count + 1)) : node.name
        
        replaceLastWord(with: "@\(relPath) ")
        isComposerFocused = true
    }

    private func applyLogToken(_ token: ChatLogToken, query: String) {
        replaceLastWord(with: "\(token.token) ")
        isComposerFocused = true
    }

    private func replaceLastWord(with newText: String) {
        var text = chatStore.composerText
        if let lastSpace = text.lastIndex(where: \.isWhitespace) {
            let prefix = text[...lastSpace]
            chatStore.composerText = String(prefix) + newText
        } else {
            chatStore.composerText = newText
        }
    }

    private func handleComposerSubmit() {
        if menuState != .none, acceptSelectedMenu() {
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
    let isShowingMenu: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAcceptMenu: () -> Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            isShowingMenu: isShowingMenu,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onAcceptMenu: onAcceptMenu,
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
        context.coordinator.isShowingMenu = isShowingMenu
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onAcceptMenu = onAcceptMenu
        context.coordinator.onSubmit = onSubmit
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        var isEnabled: Bool
        var isShowingMenu: Bool
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onAcceptMenu: () -> Bool
        var onSubmit: () -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(
            isEnabled: Bool,
            isShowingMenu: Bool,
            onMoveUp: @escaping () -> Void,
            onMoveDown: @escaping () -> Void,
            onAcceptMenu: @escaping () -> Bool,
            onSubmit: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.isShowingMenu = isShowingMenu
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onAcceptMenu = onAcceptMenu
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

                if self.isShowingMenu {
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

                    // 48 is tab, 36 is return, 76 is enter
                    if modifiers.isEmpty, [36, 48, 76].contains(event.keyCode), self.onAcceptMenu() {
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
    @State private var isThinkingExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(roleTitle, systemImage: roleIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleTint)
                Spacer()
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                Button {
                    chatStore.deleteMessage(message.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }

            if message.role == .assistant {
                if let thinking = message.thinkingContent {
                    ThinkingDisclosureView(thinking: thinking, isExpanded: $isThinkingExpanded)
                }
                AssistantMarkdownText(markdown: message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
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
            CrabTimeTheme.Palette.cyan
        case .user:
            CrabTimeTheme.Palette.panelTint
        case .system:
            CrabTimeTheme.Palette.textMuted
        case .error:
            .red
        }
    }

    private var backgroundFill: Color {
        switch message.role {
        case .assistant:
            CrabTimeTheme.Palette.raisedFill
        case .user:
            CrabTimeTheme.Palette.selectionFill
        case .system:
            CrabTimeTheme.Palette.buttonFill
        case .error:
            Color.red.opacity(0.12)
        }
    }
}

private struct ThinkingDisclosureView: View {
    let thinking: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    Text("Thinking")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CrabTimeTheme.Palette.subtleFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .interactivePointer()

            if isExpanded {
                ScrollView {
                    Text(thinking)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                }
                .frame(maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CrabTimeTheme.Palette.subtleFill.opacity(0.6))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct AssistantMarkdownText: View {
    let markdown: String

    var body: some View {
        ChatMarkdownView(markdown: markdown)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ComposerMenuState: Equatable {
    case none
    case slash(String)
    case filePicker(String)
    case logPicker(String)
}

private struct ChatLogToken: Identifiable {
    let token: String
    let detail: String
    var id: String { token }
}

private let standardLogTokens: [ChatLogToken] = [
    ChatLogToken(token: "#output", detail: "Attach latest terminal/console output"),
    ChatLogToken(token: "#diagnostics", detail: "Attach rustc diagnostics from last run"),
]
