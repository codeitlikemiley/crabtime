import Foundation

struct UnifiedProcessRunner: Sendable {
    static func run(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String] = DependencyManager.shared.defaultEnvironment,
        commandDescription: String? = nil,
        stdin: Data? = nil,
        outputLimit: Int = 1_048_576
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdinPipe: Pipe? = nil
        if stdin != nil {
            stdinPipe = Pipe()
            process.standardInput = stdinPipe
        }

        let actualCommandDescription = commandDescription ?? ([executableURL.lastPathComponent] + arguments).joined(separator: " ")

        let stdoutTask = Task.detached {
            var data = Data()
            data.reserveCapacity(outputLimit)
            
            let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            
            for await chunk in stream {
                if data.count < outputLimit {
                    data.append(chunk.prefix(outputLimit - data.count))
                }
            }
            return data
        }
        
        let stderrTask = Task.detached {
            var data = Data()
            data.reserveCapacity(outputLimit)
            
            let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            
            for await chunk in stream {
                if data.count < outputLimit {
                    data.append(chunk.prefix(outputLimit - data.count))
                }
            }
            return data
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                Task {
                    let stdoutData = await stdoutTask.value
                    let stderrData = await stderrTask.value

                    continuation.resume(
                        returning: ProcessOutput(
                            commandDescription: actualCommandDescription,
                            stdout: String(decoding: stdoutData, as: UTF8.self),
                            stderr: String(decoding: stderrData, as: UTF8.self),
                            terminationStatus: terminatedProcess.terminationStatus
                        )
                    )
                }
            }

            do {
                try process.run()
                if let stdinData = stdin, let pipe = stdinPipe {
                    pipe.fileHandleForWriting.write(stdinData)
                    try? pipe.fileHandleForWriting.close()
                }
            } catch {
                stdoutTask.cancel()
                stderrTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
