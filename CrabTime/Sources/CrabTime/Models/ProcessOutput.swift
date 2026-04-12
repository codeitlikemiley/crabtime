import Foundation

struct ProcessOutput: Sendable {
    let commandDescription: String
    let stdout: String
    let stderr: String
    let terminationStatus: Int32

    init(
        commandDescription: String,
        stdout: String,
        stderr: String,
        terminationStatus: Int32
    ) {
        self.commandDescription = commandDescription
        self.stdout = Self.sanitizeTerminalText(stdout)
        self.stderr = Self.sanitizeTerminalText(stderr)
        self.terminationStatus = terminationStatus
    }

    var combinedText: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: stdout.isEmpty || stderr.isEmpty ? "" : "\n")
    }

    private static func sanitizeTerminalText(_ text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        let normalizedLineEndings = text.replacingOccurrences(of: "\r\n", with: "\n")
        let withoutBareCarriageReturns = normalizedLineEndings.replacingOccurrences(of: "\r", with: "\n")
        return stripANSIEscapeSequences(from: withoutBareCarriageReturns)
    }

    private static func stripANSIEscapeSequences(from text: String) -> String {
        var output = String()
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            guard character == "\u{001B}" else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            let nextIndex = text.index(after: index)
            guard nextIndex < text.endIndex else {
                break
            }

            let introducer = text[nextIndex]

            if introducer == "[" {
                index = text.index(after: nextIndex)
                while index < text.endIndex {
                    let scalar = text[index].unicodeScalars.first?.value ?? 0
                    if (0x40...0x7E).contains(scalar) {
                        index = text.index(after: index)
                        break
                    }
                    index = text.index(after: index)
                }
                continue
            }

            if introducer == "]" {
                index = text.index(after: nextIndex)
                while index < text.endIndex {
                    let current = text[index]
                    if current == "\u{0007}" {
                        index = text.index(after: index)
                        break
                    }

                    if current == "\u{001B}" {
                        let terminatorIndex = text.index(after: index)
                        if terminatorIndex < text.endIndex, text[terminatorIndex] == "\\" {
                            index = text.index(after: terminatorIndex)
                            break
                        }
                    }

                    index = text.index(after: index)
                }
                continue
            }

            index = nextIndex
        }

        return output
    }
}
