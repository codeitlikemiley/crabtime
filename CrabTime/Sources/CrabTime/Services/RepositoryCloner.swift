import Foundation

struct RepositoryCloner: Sendable {
    let cloneLibraryURL: URL

    init(cloneLibraryURL: URL) {
        self.cloneLibraryURL = cloneLibraryURL
    }

    func clone(urlString: String) async throws -> URL {
        let repositorySpecifier = try normalizedRepositorySpecifier(from: urlString)
        let destinationURL = cloneLibraryURL.appendingPathComponent(repositoryName(from: repositorySpecifier), isDirectory: true)
        return try await clone(urlString: urlString, destinationURL: destinationURL, replaceExisting: false)
    }

    func clone(urlString: String, destinationURL: URL, replaceExisting: Bool) async throws -> URL {
        let repositorySpecifier = try normalizedRepositorySpecifier(from: urlString)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if replaceExisting {
                try FileManager.default.removeItem(at: destinationURL)
            } else {
                return destinationURL
            }
        }

        do {
            let result = try await UnifiedProcessRunner.run(
                arguments: [
                    "git",
                    "clone",
                    "--depth", "1",
                    repositorySpecifier,
                    destinationURL.path
                ],
                currentDirectoryURL: FileManager.default.temporaryDirectory
            )
            
            if result.terminationStatus == 0 {
                return destinationURL
            } else {
                throw CloneError.cloneFailed(message: result.combinedText)
            }
        } catch let error as CloneError {
            throw error
        } catch {
            throw CloneError.cloneFailed(message: error.localizedDescription)
        }
    }

    private func normalizedRepositorySpecifier(from urlString: String) throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw CloneError.invalidRepositoryURL
        }

        if trimmed.hasPrefix("git@") {
            return trimmed
        }

        guard let url = URL(string: trimmed), url.scheme != nil else {
            throw CloneError.invalidRepositoryURL
        }

        return trimmed
    }

    private func repositoryName(from repositorySpecifier: String) -> String {
        let normalized = repositorySpecifier
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .last?
            .replacingOccurrences(of: ".git", with: "")

        let name = normalized ?? ""
        return name.isEmpty ? UUID().uuidString : name
    }
}

extension RepositoryCloner {
    enum CloneError: LocalizedError {
        case invalidRepositoryURL
        case cloneFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .invalidRepositoryURL:
                "The repository URL is invalid."
            case .cloneFailed(let message):
                "Git clone failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }
}
