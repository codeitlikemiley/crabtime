import Foundation
import Observation

@Observable
@MainActor
final class AIModelCatalogStore {
    private(set) var modelsByProvider: [AIProviderKind: [String]] = [:]

    func models(for provider: AIProviderKind, selectedModel: String? = nil) -> [String] {
        let baseModels = modelsByProvider[provider] ?? provider.suggestedModels
        var merged = provider.suggestedModels + baseModels
        if let selectedModel, !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.append(selectedModel)
        }

        var seen = Set<String>()
        return merged
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    func preloadIfNeeded() async {
        await refreshModels(for: .openCodeCLI)
    }

    func refreshModels(for provider: AIProviderKind) async {
        switch provider {
        case .openCodeCLI:
            await refreshOpenCodeModels()
        default:
            modelsByProvider[provider] = provider.suggestedModels
        }
    }

    private func refreshOpenCodeModels() async {
        guard ToolingHealthService.resolveExecutable(named: "opencode") != nil else {
            modelsByProvider[.openCodeCLI] = AIProviderKind.openCodeCLI.suggestedModels
            return
        }

        do {
            let result = try await ToolingHealthService.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["opencode", "models"],
                currentDirectoryURL: nil
            )
            guard result.terminationStatus == 0 else {
                modelsByProvider[.openCodeCLI] = AIProviderKind.openCodeCLI.suggestedModels
                return
            }

            let dynamicModels = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { !$0.hasPrefix("zai-") }

            modelsByProvider[.openCodeCLI] = dynamicModels.isEmpty
                ? AIProviderKind.openCodeCLI.suggestedModels
                : dynamicModels
        } catch {
            modelsByProvider[.openCodeCLI] = AIProviderKind.openCodeCLI.suggestedModels
        }
    }
}
