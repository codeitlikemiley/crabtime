import Foundation

struct ProcessOutput: Sendable {
    let commandDescription: String
    let stdout: String
    let stderr: String
    let terminationStatus: Int32

    var combinedText: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: stdout.isEmpty || stderr.isEmpty ? "" : "\n")
    }
}
