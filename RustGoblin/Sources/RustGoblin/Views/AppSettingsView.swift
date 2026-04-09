import SwiftUI

struct AppSettingsView: View {
    @Environment(AISettingsStore.self) private var settingsStore
    @Environment(AIModelCatalogStore.self) private var modelCatalogStore

    @State private var toolingStatus: [ToolHealthStatus] = []
    @State private var secretDrafts: [String: String] = [:]

    private let credentialStore = CredentialStore()
    private let toolingHealthService = ToolingHealthService()

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    providerDefaultsCard

                    ForEach(AIProviderKind.defaultChatProviders) { kind in
                        providerCard(for: kind)
                    }
                }
                .padding(20)
            }
            .tabItem {
                Label("AI Providers", systemImage: "sparkles.rectangle.stack")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(toolingStatus) { tool in
                        toolingCard(tool)
                    }
                }
                .padding(20)
            }
            .tabItem {
                Label("Tooling", systemImage: "wrench.and.screwdriver")
            }
        }
        .frame(width: 880, height: 720)
        .task {
            hydrateSecrets()
            await modelCatalogStore.preloadIfNeeded()
            await refreshTooling()
        }
    }


    private var providerDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Chat Provider")
                .font(.title3.weight(.bold))

            Picker("Provider", selection: Binding(
                get: { settingsStore.defaultProvider },
                set: { settingsStore.setDefaultProvider($0) }
            )) {
                ForEach(AIProviderKind.defaultChatProviders) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)

            Text("New exercise chat sessions start with this provider and model unless you choose a different one.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RustGoblinTheme.Palette.panelFill)
        )
    }

    private func providerCard(for kind: AIProviderKind) -> some View {
        let preference = settingsStore.preference(for: kind)
        let status = toolStatus(for: kind)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.headline.weight(.bold))

                Spacer()

                Toggle("Enabled", isOn: Binding(
                    get: { preference.isEnabled },
                    set: { settingsStore.setEnabled($0, for: kind) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Text(kind.isCLI ? "Uses your local CLI subscription/runtime." : "Uses an API key stored in the macOS Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 12) {
                Text("Model")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 90, alignment: .leading)

                ModelComboBox(
                    text: Binding(
                        get: { settingsStore.preference(for: kind).model },
                        set: { settingsStore.updateModel($0, for: kind) }
                    ),
                    items: modelCatalogStore.models(
                        for: kind,
                        selectedModel: settingsStore.preference(for: kind).model
                    ),
                    placeholder: kind.defaultModel
                ) { value in
                    settingsStore.updateModel(value, for: kind)
                }
                .frame(height: 28)

                if kind == .openCodeCLI {
                    Button {
                        Task {
                            await modelCatalogStore.refreshModels(for: .openCodeCLI)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .interactivePointer()
                }
            }

            if kind.isCLI {
                if let status {
                    providerStatusRow(status)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text("API Key")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 90, alignment: .leading)

                    SecureField("sk-…", text: Binding(
                        get: { secretDrafts[kind.credentialKey] ?? "" },
                        set: { secretDrafts[kind.credentialKey] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button("Save") {
                        saveSecret(for: kind)
                    }
                    .interactivePointer()

                    Button("Clear") {
                        clearSecret(for: kind)
                    }
                    .interactivePointer()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RustGoblinTheme.Palette.panelFill)
        )
    }

    private func providerStatusRow(_ status: ToolHealthStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.isInstalled ? RustGoblinTheme.Palette.moss : .red)
                    .frame(width: 8, height: 8)

                Text(status.isInstalled ? "Installed" : "Missing")
                    .font(.footnote.weight(.semibold))

                if let version = status.version, !version.isEmpty {
                    Text(version)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if let executablePath = status.executablePath {
                Text(executablePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let guidance = status.guidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toolingCard(_ tool: ToolHealthStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tool.title)
                    .font(.headline.weight(.bold))
                Spacer()
                Text(tool.isInstalled ? "Ready" : "Missing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tool.isInstalled ? RustGoblinTheme.Palette.moss : .red)
            }

            Text(tool.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let version = tool.version, !version.isEmpty {
                Text(version)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let executablePath = tool.executablePath {
                Text(executablePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let guidance = tool.guidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RustGoblinTheme.Palette.panelFill)
        )
    }

    private func toolStatus(for kind: AIProviderKind) -> ToolHealthStatus? {
        switch kind {
        case .codexCLI:
            toolingStatus.first(where: { $0.id == "codex" })
        case .geminiCLI:
            toolingStatus.first(where: { $0.id == "gemini" })
        case .claudeCLI:
            toolingStatus.first(where: { $0.id == "claude" })
        case .openCodeCLI:
            toolingStatus.first(where: { $0.id == "opencode" })
        case .openAI, .anthropic, .geminiAPI, .openRouter:
            nil
        }
    }

    private func hydrateSecrets() {
        for kind in AIProviderKind.allCases where !kind.isCLI {
            secretDrafts[kind.credentialKey] = credentialStore.readSecret(for: kind.credentialKey) ?? ""
        }
    }

    private func saveSecret(for kind: AIProviderKind) {
        let secret = secretDrafts[kind.credentialKey] ?? ""
        do {
            try credentialStore.saveSecret(secret, for: kind.credentialKey)
        } catch {
            secretDrafts[kind.credentialKey] = error.localizedDescription
        }
    }

    private func clearSecret(for kind: AIProviderKind) {
        do {
            try credentialStore.deleteSecret(for: kind.credentialKey)
            secretDrafts[kind.credentialKey] = ""
        } catch {
            secretDrafts[kind.credentialKey] = error.localizedDescription
        }
    }

    private func refreshTooling() async {
        toolingStatus = await toolingHealthService.collectStatus(exercismCLI: ExercismCLI())
    }
}
