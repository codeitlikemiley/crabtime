import Foundation
import Combine
import OSLog

@Observable
final class DependencyManager: @unchecked Sendable {
    static let shared = DependencyManager()
    
    enum Status: Equatable {
        case unknown
        case checking
        case missing(needsRust: Bool, needsExercism: Bool)
        case installing(component: String, progress: Double, message: String)
        case ready
        case failed(error: String)
    }
    
    var status: Status = .unknown
    
    private let logger = Logger(subsystem: AppBrand.bundleIdentifier, category: "DependencyManager")
    
    /// Returns an augmented PATH string that includes standard homebrew, local user, and rustup directories.
    /// Use this for all `Process.environment["PATH"]` injections.
    var augmentedPath: String {
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let additionalPaths = [
            (FileManager.default.homeDirectoryForCurrentUser.path + "/.cargo/bin"),
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin"
        ]
        
        var currentPaths = systemPath.components(separatedBy: ":")
        for path in additionalPaths {
            if !currentPaths.contains(path) {
                currentPaths.append(path)
            }
        }
        return currentPaths.joined(separator: ":")
    }
    
    var defaultEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPath
        env["HOME"] = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        env["USER"] = env["USER"] ?? NSUserName()
        env["LOGNAME"] = env["LOGNAME"] ?? NSUserName()
        env["SHELL"] = env["SHELL"] ?? "/bin/zsh"
        env["TMPDIR"] = env["TMPDIR"] ?? NSTemporaryDirectory()
        return env
    }
    
    func checkDependencies() async {
        await MainActor.run { status = .checking }
        
        let hasCargo = await checkBinary(name: "cargo")
        let hasRustc = await checkBinary(name: "rustc")
        let hasRust = hasCargo && hasRustc
        let hasExercism = await checkBinary(name: "exercism")
        
        await MainActor.run {
            if hasRust && hasExercism {
                status = .ready
            } else {
                status = .missing(needsRust: !hasRust, needsExercism: !hasExercism)
            }
        }
    }
    
    private func checkBinary(name: String) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        task.environment = defaultEnvironment
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func installMissingDependencies() async {
        guard case let .missing(needsRust, needsExercism) = status else { return }
        
        do {
            // Because Exercism often needs Rust/Cargo folder structure to dump `exercism` into `~/.cargo/bin`,
            // we should install Rust first if needed.
            
            if needsRust {
                try await installRust()
            }
            
            if needsExercism {
                try await installExercism()
            }
            
            await MainActor.run {
                status = .ready
            }
        } catch {
            await MainActor.run {
                status = .failed(error: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Handlers
    
    private func installRust() async throws {
        await MainActor.run { status = .installing(component: "Rust", progress: 0.1, message: "Downloading rustup...") }
        
        let rustupURL = URL(string: "https://sh.rustup.rs")!
        let (scriptData, response) = try await URLSession.shared.data(from: rustupURL)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "DependencyManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download rustup script: \(response)"])
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("rustup-init.sh")
        try scriptData.write(to: scriptURL)
        
        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        attrs[.posixPermissions] = NSNumber(value: 0o755)
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptURL.path)
        
        await MainActor.run { status = .installing(component: "Rust", progress: 0.5, message: "Installing Rust toolchain...") }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, "-y"] // -y disables prompts
        process.environment = defaultEnvironment
        
        try process.run()
        process.waitUntilExit()
        
        try? FileManager.default.removeItem(at: scriptURL)
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "DependencyManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "rustup installation failed with status \(process.terminationStatus)"])
        }
    }
    
    private func installExercism() async throws {
        await MainActor.run { status = .installing(component: "Exercism CLI", progress: 0.1, message: "Locating latest release...") }
        
        // Use GitHub API to find the latest release
        let apiURL = URL(string: "https://api.github.com/repos/exercism/cli/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let assets = json?["assets"] as? [[String: Any]] ?? []
        
        // Determine architecture
        var sysinfo = utsname()
        uname(&sysinfo)
        let machineString = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        } ?? "unknown"
        
        let isArm = machineString.contains("arm") || machineString.contains("aarch64")
        let targetArchRaw = isArm ? "arm64" : "x86_64"
        // E.g., exercism-3.5.3-mac-arm64.tar.gz or exercism-3.5.3-mac-x86_64.tar.gz
        let targetAssetSearch = "mac-\(targetArchRaw).tar.gz"
        
        guard let targetAsset = assets.first(where: { ($0["name"] as? String ?? "").contains(targetAssetSearch) }),
              let downloadURLString = targetAsset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            throw NSError(domain: "DependencyManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not locate suitable Exercism binary for \(machineString)"])
        }
        
        await MainActor.run { status = .installing(component: "Exercism CLI", progress: 0.5, message: "Downloading binary...") }
        
        let (tarData, _) = try await URLSession.shared.data(from: downloadURL)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tarURL = tempDir.appendingPathComponent("exercism.tar.gz")
        try tarData.write(to: tarURL)
        
        await MainActor.run { status = .installing(component: "Exercism CLI", progress: 0.8, message: "Extracting...") }
        
        // Extract
        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["-xzf", tarURL.path, "-C", tempDir.path]
        try tarProcess.run()
        tarProcess.waitUntilExit()
        
        let extractedBinaryURL = tempDir.appendingPathComponent("exercism")
        guard FileManager.default.fileExists(atPath: extractedBinaryURL.path) else {
            throw NSError(domain: "DependencyManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to extract exercism binary"])
        }
        
        // Ensure destination dir exists (like ~/.cargo/bin)
        let homeBinRaw = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin")
        if !FileManager.default.fileExists(atPath: homeBinRaw.path) {
            try FileManager.default.createDirectory(at: homeBinRaw, withIntermediateDirectories: true)
        }
        
        let finalDest = homeBinRaw.appendingPathComponent("exercism")
        if FileManager.default.fileExists(atPath: finalDest.path) {
            try FileManager.default.removeItem(at: finalDest)
        }
        
        try FileManager.default.moveItem(at: extractedBinaryURL, to: finalDest)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
}
