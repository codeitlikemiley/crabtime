import Foundation
import Observation

@Observable
@MainActor
final class ChatStore {
    var sessions: [ExerciseChatSession] = []
    var messages: [ExerciseChatMessage] = []
    var selectedSessionID: UUID?
    var composerText: String = ""
    var isSending: Bool = false
    var errorMessage: String?

    @ObservationIgnored private let database: WorkspaceLibraryDatabase
    @ObservationIgnored let providerManager: AIProviderManager
    @ObservationIgnored private let contextBuilder: ExerciseContextBuilder
    @ObservationIgnored weak var processStore: ProcessStore?

    init(
        database: WorkspaceLibraryDatabase,
        providerManager: AIProviderManager,
        contextBuilder: ExerciseContextBuilder = ExerciseContextBuilder()
    ) {
        self.database = database
        self.providerManager = providerManager
        self.contextBuilder = contextBuilder
    }

    var selectedSession: ExerciseChatSession? {
        guard let selectedSessionID else {
            return sessions.first
        }
        return sessions.first { $0.id == selectedSessionID }
    }

    func selectedProvider(using settingsStore: AISettingsStore) -> AIProviderKind {
        selectedSession?.providerKind ?? settingsStore.defaultProvider
    }

    func selectedModel(using settingsStore: AISettingsStore) -> String {
        selectedSession?.model ?? settingsStore.preference(for: settingsStore.defaultProvider).model
    }

    func attachProcessStore(_ store: ProcessStore) {
        self.processStore = store
    }

    func syncSelection(using store: WorkspaceStore) {
        guard let scope = currentScope(using: store) else {
            sessions = []
            messages = []
            selectedSessionID = nil
            return
        }

        do {
            let fetchedSessions = try fetchSessions(for: scope)
            sessions = fetchedSessions

            if let savedSessionID = store.selectedChatSessionID,
               fetchedSessions.contains(where: { $0.id == savedSessionID }) {
                selectedSessionID = savedSessionID
            } else {
                selectedSessionID = fetchedSessions.first?.id
            }

            try loadMessagesForSelectedSession()
        } catch {
            sessions = []
            messages = []
            selectedSessionID = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectSession(_ sessionID: UUID?, using store: WorkspaceStore) {
        selectedSessionID = sessionID
        store.selectedChatSessionID = sessionID
        do {
            try loadMessagesForSelectedSession()
        } catch {
            errorMessage = error.localizedDescription
        }
        store.persistChatSelection()
    }

    func createSession(using store: WorkspaceStore, providerKind: AIProviderKind? = nil) {
        guard let scope = currentScope(using: store) else {
            return
        }

        let resolvedProvider = providerKind ?? providerManager.settingsStore.defaultProvider
        let session = ExerciseChatSession(
            workspaceRootPath: scope.workspaceRootPath,
            exercisePath: scope.scopePath,
            title: scope.defaultSessionTitle,
            providerKind: resolvedProvider,
            model: providerManager.displayModel(for: resolvedProvider)
        )

        do {
            try database.upsertChatSession(session)
            sessions.insert(session, at: 0)
            selectSession(session.id, using: store)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedProvider(_ provider: AIProviderKind, using store: WorkspaceStore, settingsStore: AISettingsStore) {
        let previousProvider = selectedSession?.providerKind
        settingsStore.setDefaultProvider(provider)

        guard var session = selectedSession else {
            return
        }

        // Shut down the old provider's ACP connections if switching away from it
        if let previousProvider, previousProvider != provider {
            let oldTransport = settingsStore.preference(for: previousProvider).transport
            if oldTransport == .acp {
                Task {
                    await providerManager.shutdownProvider(
                        previousProvider,
                        reason: "provider switched to \(provider.title)",
                        eventSink: { event in
                        Task { @MainActor [weak self] in
                            self?.processStore?.handleAITransportEvent(event)
                        }
                    }
                    )
                }
            }
        }

        session.providerKind = provider
        session.model = settingsStore.preference(for: provider).model
        session.backendSessionID = nil
        session.updatedAt = Date()

        do {
            try database.upsertChatSession(session)
            replaceSession(session)
            store.selectedChatSessionID = session.id
            store.persistChatSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedModel(_ model: String, using store: WorkspaceStore, settingsStore: AISettingsStore) {
        let resolvedProvider = selectedProvider(using: settingsStore)
        settingsStore.updateModel(model, for: resolvedProvider)

        guard var session = selectedSession else {
            return
        }

        session.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        session.updatedAt = Date()

        do {
            try database.upsertChatSession(session)
            replaceSession(session)
            store.persistChatSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCurrentSession(using store: WorkspaceStore) {
        guard let session = selectedSession else {
            return
        }

        do {
            try database.deleteMessages(for: session.id)
            messages = []
            var updatedSession = session
            updatedSession.backendSessionID = nil
            updatedSession.updatedAt = Date()
            try database.upsertChatSession(updatedSession)
            replaceSession(updatedSession)
            store.persistChatSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetSelectedWarmSession(using store: WorkspaceStore) {
        guard var session = selectedSession else {
            return
        }

        session.backendSessionID = nil
        session.updatedAt = Date()

        do {
            try database.upsertChatSession(session)
            replaceSession(session)
            processStore?.handleAITransportEvent(.note(provider: session.providerKind, message: "Warm ACP session reset. The next send will create a new session."))
            store.persistChatSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reconnectSelectedACP(using store: WorkspaceStore) {
        guard let session = selectedSession else {
            return
        }

        Task {
            await providerManager.restartACPConnection(
                session: session,
                eventSink: { event in
                    Task { @MainActor [weak self] in
                        self?.processStore?.handleAITransportEvent(event)
                    }
                }
            )
            await MainActor.run {
                processStore?.handleAITransportEvent(.note(provider: session.providerKind, message: "ACP connection restarted."))
            }
        }
    }

    func sendCurrentMessage(using store: WorkspaceStore) {
        guard !isSending else {
            return
        }

        let userMessage = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else {
            return
        }

        composerText = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                var activeMessage = userMessage

                if let commandResult = try await store.handleChatSlashCommand(userMessage) {
                    switch commandResult {
                    case .localReply(let localReply):
                        try await handleLocalSlashCommandReply(localReply, userMessage: userMessage, using: store)
                        return
                    case .rewritePrompt(let prompt):
                        activeMessage = prompt
                    }
                }

                if selectedSession == nil {
                    await MainActor.run {
                        createSession(using: store)
                    }
                }

                guard let session = selectedSession else {
                    await MainActor.run {
                        errorMessage = "Unable to start a chat session."
                        isSending = false
                    }
                    return
                }

                let outgoingMessage = ExerciseChatMessage(sessionID: session.id, role: .user, content: activeMessage)
                try database.insertChatMessage(outgoingMessage)
                await MainActor.run {
                    messages.append(outgoingMessage)
                }

                var updatedSession = session
                if updatedSession.title == defaultSessionTitle(using: store) {
                    updatedSession.title = userMessage
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .prefix(48)
                        .description
                }
                updatedSession.updatedAt = Date()
                try database.upsertChatSession(updatedSession)

                let transport = await MainActor.run {
                    providerManager.settingsStore.preference(for: updatedSession.providerKind).transport
                }
                await MainActor.run {
                    processStore?.handleAITransportEvent(
                        .transportSelected(
                            provider: updatedSession.providerKind,
                            transport: transport,
                            model: updatedSession.model
                        )
                    )
                }

                let tokens = store.workspace.map { 
                    ChatContextTokenParser.parse(activeMessage, workspaceRoot: $0.rootURL)
                } ?? []

                let context = contextBuilder.build(from: store, processStore: processStore, contextTokens: tokens)
                
                let reply = try await providerManager.sendMessage(
                    session: updatedSession,
                    messages: messages + [outgoingMessage],
                    context: context,
                    eventSink: { event in
                        Task { @MainActor [weak self] in
                            self?.processStore?.handleAITransportEvent(event)
                        }
                    }
                )
                updatedSession.backendSessionID = reply.backendSessionID ?? updatedSession.backendSessionID

                let assistantMessage = ExerciseChatMessage(sessionID: updatedSession.id, role: .assistant, content: reply.content, thinkingContent: reply.thinkingContent)
                try database.insertChatMessage(assistantMessage)
                try database.upsertChatSession(updatedSession)

                await MainActor.run {
                    replaceSession(updatedSession)
                    messages.append(assistantMessage)
                    isSending = false
                    store.selectedChatSessionID = updatedSession.id
                    if reply.didRecoverStaleSession {
                        processStore?.handleAITransportEvent(.note(provider: updatedSession.providerKind, message: "Recovered from stale ACP session without clearing chat history."))
                    }
                    store.persistChatSelection()
                }
            } catch {
                let errorMessage = selectedSession.map {
                    ExerciseChatMessage(
                        sessionID: $0.id,
                        role: .error,
                        content: error.localizedDescription,
                        status: .failed
                    )
                }
                if let errorMessage {
                    try? database.insertChatMessage(errorMessage)
                }

                await MainActor.run {
                    if let errorMessage {
                        self.messages.append(errorMessage)
                    }
                    let failedProvider = selectedSession?.providerKind ?? providerManager.settingsStore.defaultProvider
                    let isACP = providerManager.transport(for: failedProvider) == .acp
                    if isACP {
                        processStore?.handleAITransportEvent(.transportError(
                            provider: failedProvider,
                            message: error.localizedDescription,
                            logFilePath: processStore?.aiRuntimeLogPath
                        ))
                        self.errorMessage = "ACP chat failed. Open AI Runtime for status and logs. \(error.localizedDescription)"
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isSending = false
                }
            }
        }
    }

    private func handleLocalSlashCommandReply(
        _ localReply: String,
        userMessage: String,
        using store: WorkspaceStore
    ) async throws {
        await MainActor.run {
            syncSelection(using: store)
        }

        if selectedSession == nil {
            await MainActor.run {
                createSession(using: store)
            }
        }

        guard let session = selectedSession else {
            await MainActor.run {
                errorMessage = localReply
                isSending = false
            }
            return
        }

        let outgoingMessage = ExerciseChatMessage(sessionID: session.id, role: .user, content: userMessage)
        try database.insertChatMessage(outgoingMessage)

        var updatedSession = session
        if updatedSession.title == defaultSessionTitle(using: store) {
            updatedSession.title = userMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(48)
                .description
        }
        updatedSession.updatedAt = Date()
        try database.upsertChatSession(updatedSession)

        let assistantMessage = ExerciseChatMessage(
            sessionID: updatedSession.id,
            role: .assistant,
            content: localReply
        )
        try database.insertChatMessage(assistantMessage)

        await MainActor.run {
            replaceSession(updatedSession)
            if !messages.contains(where: { $0.id == outgoingMessage.id }) {
                messages.append(outgoingMessage)
            }
            messages.append(assistantMessage)
            isSending = false
            store.selectedChatSessionID = updatedSession.id
            store.persistChatSelection()
        }
    }

    func deleteMessage(_ messageID: UUID) {
        do {
            try database.deleteMessage(id: messageID)
            messages.removeAll { $0.id == messageID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMessagesForSelectedSession() throws {
        guard let sessionID = selectedSessionID else {
            messages = []
            return
        }
        messages = try database.fetchMessages(for: sessionID)
    }

    private func replaceSession(_ session: ExerciseChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            sessions.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    private func defaultSessionTitle(using store: WorkspaceStore) -> String {
        currentScope(using: store)?.defaultSessionTitle ?? "Chat"
    }

    private func currentScope(using store: WorkspaceStore) -> ChatScope? {
        if let workspace = store.workspace {
            let workspaceRootPath = workspace.rootURL.standardizedFileURL.path

            if let exercise = store.selectedExercise {
                return ChatScope(
                    workspaceRootPath: workspaceRootPath,
                    scopePath: exercise.chatScopeURL.standardizedFileURL.path,
                    legacySourcePath: exercise.sourceURL.standardizedFileURL.path,
                    defaultSessionTitle: "\(exercise.title) Chat"
                )
            }

            return ChatScope(
                workspaceRootPath: workspaceRootPath,
                scopePath: workspaceChatScopePath(for: workspaceRootPath),
                legacySourcePath: workspaceChatScopePath(for: workspaceRootPath),
                defaultSessionTitle: "\(workspace.title) Chat"
            )
        }

        return ChatScope(
            workspaceRootPath: "",
            scopePath: Self.globalChatScopePath,
            legacySourcePath: Self.globalChatScopePath,
            defaultSessionTitle: "General Chat"
        )
    }

    private func workspaceChatScopePath(for workspaceRootPath: String) -> String {
        "\(Self.workspaceChatScopePrefix)\(workspaceRootPath)"
    }

    private func fetchSessions(for scope: ChatScope) throws -> [ExerciseChatSession] {
        var fetchedSessions = try database.fetchChatSessions(
            workspaceRootPath: scope.workspaceRootPath,
            exercisePath: scope.scopePath
        )

        guard fetchedSessions.isEmpty, scope.legacySourcePath != scope.scopePath else {
            return fetchedSessions
        }

        let legacySessions = try database.fetchChatSessions(
            workspaceRootPath: scope.workspaceRootPath,
            exercisePath: scope.legacySourcePath
        )

        guard !legacySessions.isEmpty else {
            return fetchedSessions
        }

        for legacySession in legacySessions {
            let migratedSession = ExerciseChatSession(
                id: legacySession.id,
                workspaceRootPath: scope.workspaceRootPath,
                exercisePath: scope.scopePath,
                title: legacySession.title,
                providerKind: legacySession.providerKind,
                model: legacySession.model,
                backendSessionID: legacySession.backendSessionID,
                createdAt: legacySession.createdAt,
                updatedAt: legacySession.updatedAt
            )
            try database.upsertChatSession(migratedSession)
        }

        fetchedSessions = try database.fetchChatSessions(
            workspaceRootPath: scope.workspaceRootPath,
            exercisePath: scope.scopePath
        )
        return fetchedSessions
    }
}

private struct ChatScope {
    let workspaceRootPath: String
    let scopePath: String
    let legacySourcePath: String
    let defaultSessionTitle: String
}

private extension ChatStore {
    static let workspaceChatScopePrefix = "__rustgoblin_workspace_chat__:"
    static let globalChatScopePath = "__rustgoblin_global_chat__"
}
