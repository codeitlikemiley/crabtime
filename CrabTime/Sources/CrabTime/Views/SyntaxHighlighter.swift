import AppKit

// MARK: - Shared Syntax Highlighting Engine

enum SyntaxHighlighter {
    static var font: NSFont { NSFont.monospacedSystemFont(ofSize: 15, weight: .regular) }
    static var foreground: NSColor { NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1) }

    /// Apply syntax highlighting to a text view based on file extension.
    @MainActor
    static func apply(to textView: NSTextView, fileExtension: String? = nil) {
        guard let textStorage = textView.textStorage else { return }

        let string = textView.string
        let fullRange = NSRange(location: 0, length: string.utf16.count)

        textStorage.beginEditing()
        textStorage.setAttributes(
            [.font: font, .foregroundColor: foreground],
            range: fullRange
        )

        let rules: [(NSRegularExpression, NSColor)]
        switch fileExtension?.lowercased() {
        case "rs":
            rules = RustSyntax.rules
        case "toml":
            rules = TomlSyntax.rules
        default:
            rules = RustSyntax.rules // default to Rust for this app
        }

        for (regex, color) in rules {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                guard let match else { return }
                textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        textStorage.endEditing()
        textView.typingAttributes = [.font: font, .foregroundColor: foreground]
    }
}

// MARK: - Rust Syntax

private enum RustSyntax {
    static let rules: [(NSRegularExpression, NSColor)] = [
        (try! NSRegularExpression(pattern: #"\b(fn|let|mut|pub|use|mod|struct|enum|impl|match|if|else|loop|while|for|in|return|async|await|move|where|trait|const|static|crate|self|super|type|ref|break|continue|unsafe|extern|dyn|as|true|false)\b"#), Palette.keyword),
        (try! NSRegularExpression(pattern: #"\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|String|str|Self|Option|Result|Vec|Box|Rc|Arc|HashMap|HashSet|BTreeMap|BTreeSet|Ordering|None|Some|Ok|Err)\b"#), Palette.type),
        (try! NSRegularExpression(pattern: #""([^"\\]|\\.)*""#), Palette.string),
        (try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#), Palette.number),
        (try! NSRegularExpression(pattern: #"(?m)//.*$"#), Palette.comment),
        (try! NSRegularExpression(pattern: #"#\[[^\]]+\]"#), Palette.attribute),
        (try! NSRegularExpression(pattern: #"\b[a-zA-Z_][a-zA-Z0-9_]*!"#), Palette.macro),
    ]
}

// MARK: - TOML Syntax

private enum TomlSyntax {
    static let rules: [(NSRegularExpression, NSColor)] = [
        // Comments
        (try! NSRegularExpression(pattern: #"(?m)#.*$"#), Palette.comment),
        // Section headers: [section] or [[array]]
        (try! NSRegularExpression(pattern: #"^\s*\[{1,2}[^\]]+\]{1,2}"#, options: .anchorsMatchLines), Palette.attribute),
        // Keys (before =)
        (try! NSRegularExpression(pattern: #"(?m)^[A-Za-z_][A-Za-z0-9_.-]*(?=\s*=)"#), Palette.keyword),
        // Strings (double-quoted and triple-quoted)
        (try! NSRegularExpression(pattern: #""{3}[\s\S]*?"{3}|"([^"\\]|\\.)*""#), Palette.string),
        // Booleans
        (try! NSRegularExpression(pattern: #"\b(true|false)\b"#), Palette.type),
        // Numbers
        (try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#), Palette.number),
    ]
}

// MARK: - Shared Palette

private enum Palette {
    static let keyword   = NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.66, alpha: 1)
    static let type      = NSColor(calibratedRed: 0.56, green: 0.82, blue: 1.0, alpha: 1)
    static let string    = NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.58, alpha: 1)
    static let number    = NSColor(calibratedRed: 0.47, green: 0.84, blue: 0.63, alpha: 1)
    static let comment   = NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.63, alpha: 1)
    static let attribute = NSColor(calibratedRed: 0.93, green: 0.57, blue: 0.73, alpha: 1)
    static let macro     = NSColor(calibratedRed: 0.90, green: 0.67, blue: 1.0, alpha: 1)
}
