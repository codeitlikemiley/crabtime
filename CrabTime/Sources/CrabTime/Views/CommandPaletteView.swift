import SwiftUI

@MainActor
struct CommandPaletteView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Environment(ProcessStore.self) private var processStore
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    private var commands: [PaletteCommand] {
        var all: [PaletteCommand] = []

        // Parse go-to-line from query — if user typed a line number, show it first
        if let lineNumber = parseGoToLine(query) {
            all.append(
                PaletteCommand(
                    id: "goto_\(lineNumber)",
                    title: "Go to Line \(lineNumber)",
                    icon: "arrow.right.to.line",
                    shortcut: nil,
                    keywords: []
                )
            )
        }

        all.append(contentsOf: [
            // Navigation
            PaletteCommand(
                id: "goto_line",
                title: "Go to Line…",
                icon: "arrow.right.to.line",
                shortcut: ":N",
                keywords: ["go", "line", "jump", "goto", "navigate", ":"]
            ),

            // Editor
            PaletteCommand(
                id: "toggle_line_numbers",
                title: store.showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers",
                icon: "list.number",
                shortcut: nil,
                keywords: ["line", "number", "gutter", "show", "hide"]
            ),
        ])

        // Contextual: View Solution (only when a solution exists for current exercise)
        if store.hasSolutionPreview {
            all.append(
                PaletteCommand(
                    id: "view_solution",
                    title: "View Solution",
                    icon: "lightbulb.max",
                    shortcut: nil,
                    keywords: ["solution", "answer", "view", "show", "reveal", "hint"]
                )
            )
        }

        all.append(contentsOf: [
            // Sidebar & Layout
            PaletteCommand(
                id: "toggle_left_sidebar",
                title: navigationStore.showsProblemPane ? "Hide Left Sidebar" : "Show Left Sidebar",
                icon: "sidebar.left",
                shortcut: "⌘B",
                keywords: ["sidebar", "left", "toggle", "explorer", "panel"]
            ),
            PaletteCommand(
                id: "toggle_right_sidebar",
                title: navigationStore.isInspectorVisible ? "Hide Right Sidebar" : "Show Right Sidebar",
                icon: "sidebar.right",
                shortcut: "⇧⌘B",
                keywords: ["sidebar", "right", "toggle", "inspector"]
            ),

            // Focus
            PaletteCommand(
                id: "focus_chat",
                title: "Focus Chat",
                icon: "bubble.left.and.text.bubble.right",
                shortcut: "⌘I",
                keywords: ["chat", "ai", "message", "composer", "focus"]
            ),
            PaletteCommand(
                id: "focus_inspector",
                title: "Show Inspector",
                icon: "info.circle",
                shortcut: "⇧⌘I",
                keywords: ["inspector", "info", "sidebar", "right", "details"]
            ),
            PaletteCommand(
                id: "focus_explorer",
                title: "Show File Explorer",
                icon: "folder",
                shortcut: "⌘F",
                keywords: ["file", "explorer", "search", "browse", "tree"]
            ),
            PaletteCommand(
                id: "focus_exercises",
                title: "Focus Exercise Search",
                icon: "magnifyingglass",
                shortcut: "⌘E",
                keywords: ["exercise", "search", "library", "find"]
            ),

            // Terminal
            PaletteCommand(
                id: "toggle_terminal",
                title: navigationStore.showsTerminal ? "Hide Terminal" : "Show Terminal",
                icon: "terminal",
                shortcut: "⌘J",
                keywords: ["terminal", "console", "output", "toggle"]
            ),
            PaletteCommand(
                id: "maximize_terminal",
                title: navigationStore.isTerminalMaximized ? "Restore Terminal" : "Maximize Terminal",
                icon: navigationStore.isTerminalMaximized ? "arrow.down.right.and.arrow.up.left" : "rectangle.bottomthird.inset.filled",
                shortcut: "⇧⌘M",
                keywords: ["terminal", "maximize", "restore", "fullscreen"]
            ),
            PaletteCommand(
                id: "clear_output",
                title: "Clear Output",
                icon: "trash",
                shortcut: "⌘K",
                keywords: ["clear", "output", "terminal", "clean"]
            ),

            // Console Tabs
            PaletteCommand(
                id: "show_output_tab",
                title: "Show Output Tab",
                icon: "text.alignleft",
                shortcut: "⇧⌘O",
                keywords: ["output", "tab", "console", "stdout"]
            ),
            PaletteCommand(
                id: "show_diagnostics_tab",
                title: "Show Diagnostics Tab",
                icon: "exclamationmark.triangle",
                shortcut: "⇧⌘D",
                keywords: ["diagnostics", "errors", "warnings", "tab"]
            ),
            PaletteCommand(
                id: "show_session_tab",
                title: "Show Session Tab",
                icon: "clock",
                shortcut: "⇧⌘S",
                keywords: ["session", "log", "history", "tab"]
            ),
            PaletteCommand(
                id: "show_ai_runtime_tab",
                title: "Show AI Runtime Tab",
                icon: "bolt.horizontal.circle",
                shortcut: "⇧⌘A",
                keywords: ["ai", "runtime", "acp", "tools", "auth", "tab"]
            ),

            // Workspace Actions
            PaletteCommand(
                id: "run_exercise",
                title: "Run Exercise",
                icon: "play.fill",
                shortcut: "⌘R",
                keywords: ["run", "execute", "compile", "build"]
            ),
            PaletteCommand(
                id: "run_tests",
                title: "Run Tests",
                icon: "checkmark.diamond",
                shortcut: "⌘T",
                keywords: ["test", "tests", "run", "check", "verify"]
            ),
            PaletteCommand(
                id: "save_exercise",
                title: "Save Exercise",
                icon: "square.and.arrow.down",
                shortcut: "⌘S",
                keywords: ["save", "write", "file"]
            ),
            PaletteCommand(
                id: "close_file",
                title: "Close File",
                icon: "xmark.square",
                shortcut: "⌘W",
                keywords: ["close", "file", "tab"]
            ),

            // Workspace Management
            PaletteCommand(
                id: "new_workspace",
                title: "New Workspace…",
                icon: "plus.square",
                shortcut: "⌘N",
                keywords: ["new", "workspace", "create"]
            ),
            PaletteCommand(
                id: "import_exercises",
                title: "Import Exercises…",
                icon: "folder.badge.plus",
                shortcut: "⌘O",
                keywords: ["import", "open", "folder", "exercises"]
            ),
            PaletteCommand(
                id: "clone_repo",
                title: "Clone Repository…",
                icon: "arrow.triangle.branch",
                shortcut: "⇧⌘G",
                keywords: ["clone", "git", "repository", "github"]
            ),
            PaletteCommand(
                id: "workspace_palette",
                title: "Open Workspace Palette",
                icon: "tray.2",
                shortcut: "⇧⌘P",
                keywords: ["workspace", "switch", "palette", "picker"]
            ),
            PaletteCommand(
                id: "override_cargo_prompt",
                title: "Override Cargo Runner…",
                icon: "slider.horizontal.3",
                shortcut: nil,
                keywords: ["override", "cargo", "runner", "config", "args", "test", "ignore"]
            ),
        ])

        if query.isEmpty {
            return all
        }

        let lowered = query.lowercased().trimmingCharacters(in: .whitespaces)

        // If the query starts with ":" treat it as a go-to-line intent
        if lowered.hasPrefix(":") {
            return all.filter { $0.id.hasPrefix("goto_") }
        }
        
        // If the query starts with ">" treat it as cargo runner override
        if query.hasPrefix(">") {
            let args = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
            return [
                PaletteCommand(
                    id: "run_cargo_override",
                    title: args.isEmpty ? "Type override tokens (e.g. /--include-ignored)" : "Apply Override: cargo runner override -- \(args)",
                    icon: "slider.horizontal.3",
                    shortcut: "↵",
                    keywords: []
                )
            ]
        }

        // Score and rank results
        let scored: [(command: PaletteCommand, score: Int)] = all.compactMap { cmd in
            let score = matchScore(query: lowered, command: cmd)
            return score > 0 ? (cmd, score) : nil
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.command)
    }

    /// Compute a relevance score for a command against the query.
    /// Higher = better match. 0 = no match.
    private func matchScore(query: String, command: PaletteCommand) -> Int {
        let title = command.title.lowercased()
        var score = 0

        // Dynamic goto commands (e.g. goto_50) always match
        if command.id.starts(with: "goto_") && command.id != "goto_line" {
            return 200
        }

        // Title starts with query → best possible match
        if title.hasPrefix(query) {
            score = max(score, 100)
        }

        // A word in the title starts with query (e.g. "inspector" matches "Show Inspector")
        let titleWords = title.components(separatedBy: .whitespaces)
        if titleWords.contains(where: { $0.hasPrefix(query) }) {
            score = max(score, 90)
        }

        // Title contains query as substring
        if title.contains(query) {
            score = max(score, 70)
        }

        // Keyword exact match
        if command.keywords.contains(query) {
            score = max(score, 60)
        }

        // Keyword starts with query
        if command.keywords.contains(where: { $0.hasPrefix(query) }) {
            score = max(score, 50)
        }

        // Keyword contains query
        if command.keywords.contains(where: { $0.contains(query) }) {
            score = max(score, 30)
        }

        // Fuzzy: all query characters appear in order in the title
        if score == 0 {
            var titleIndex = title.startIndex
            var matched = true
            for char in query {
                if let found = title[titleIndex...].firstIndex(of: char) {
                    titleIndex = title.index(after: found)
                } else {
                    matched = false
                    break
                }
            }
            if matched {
                score = 10
            }
        }

        return score
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                TextField("Type a command or :line to jump…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .focused($isFocused)
                    .onSubmit {
                        executeSelected()
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .background(CrabTimeTheme.Palette.divider)

            // Command list
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            Button {
                                executeCommand(command)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: command.icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(
                                            index == selectedIndex
                                                ? CrabTimeTheme.Palette.ink
                                                : CrabTimeTheme.Palette.ember
                                        )
                                        .frame(width: 20)

                                    Text(command.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(CrabTimeTheme.Palette.ink)

                                    Spacer()

                                    if let shortcut = command.shortcut {
                                        Text(shortcut)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(Color.white.opacity(0.06))
                                            )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            index == selectedIndex
                                                ? CrabTimeTheme.Palette.ember.opacity(0.2)
                                                : Color.white.opacity(0.04)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .id(command.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 360)
                .onChange(of: selectedIndex) { _, newValue in
                    let cmds = commands
                    if cmds.indices.contains(newValue) {
                        withAnimation(.easeOut(duration: 0.1)) {
                            scrollProxy.scrollTo(cmds[newValue].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CrabTimeTheme.Palette.panelFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
        .onAppear {
            isFocused = true
            selectedIndex = 0
            
            if !store.commandPaletteInitialQuery.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    await MainActor.run {
                        if self.query.isEmpty {
                            self.query = store.commandPaletteInitialQuery
                        }
                    }
                }
            } else {
                query = ""
            }
        }
        .onExitCommand {
            store.hideCommandPalette()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        // Track Cmd+P selection delta from outside
        .onChange(of: store.commandPaletteSelectionDelta) { _, _ in
            moveSelectionDown()
        }
        .background(
            PaletteKeyboardHandler(
                onMoveUp: moveSelectionUp,
                onMoveDown: moveSelectionDown,
                onConfirm: executeSelected,
                onDismiss: { store.hideCommandPalette() }
            )
        )
    }

    // MARK: - Selection

    private func moveSelectionUp() {
        let count = commands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    private func moveSelectionDown() {
        let count = commands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    private func executeSelected() {
        let cmds = commands
        guard cmds.indices.contains(selectedIndex) else { return }
        executeCommand(cmds[selectedIndex])
    }

    // MARK: - Parsing

    private func parseGoToLine(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // `:50` syntax
        if trimmed.hasPrefix(":"), let num = Int(trimmed.dropFirst()), num > 0 {
            return num
        }

        // "go to line 50" / "go to 50" / "line 50"
        let lowered = trimmed.lowercased()
            .replacingOccurrences(of: "go to line", with: "")
            .replacingOccurrences(of: "go to", with: "")
            .replacingOccurrences(of: "line", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let num = Int(lowered), num > 0 {
            return num
        }

        return nil
    }

    // MARK: - Execution

    private func executeCommand(_ command: PaletteCommand) {
        switch command.id {
        // Line numbers
        case "toggle_line_numbers":
            store.toggleLineNumbers()
        case "goto_line":
            query = ":"
            return // don't dismiss
        case "override_cargo_prompt":
            query = "> "
            return // don't dismiss
        case "run_cargo_override":
            let args = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
            Task {
                await store.applyCargoRunnerOverride(args: args)
            }

        // Solution
        case "view_solution":
            store.openSolutionFile()

        // Layout
        case "toggle_left_sidebar":
            store.toggleLeftColumnVisibility()
        case "toggle_right_sidebar":
            navigationStore.toggleInspector()

        // Focus
        case "focus_chat":
            store.focusChatComposer()
        case "focus_inspector":
            store.focusInspectorSidebar()
        case "focus_explorer":
            store.showExplorerAndFocusSearch()
        case "focus_exercises":
            store.showExerciseLibraryAndFocusSearch()

        // Terminal
        case "toggle_terminal":
            navigationStore.toggleTerminalVisibility()
        case "maximize_terminal":
            navigationStore.toggleTerminalMaximize()
        case "clear_output":
            store.clearConsoleOutput()

        // Console tabs
        case "show_output_tab":
            navigationStore.selectedConsoleTab = .output
        case "show_diagnostics_tab":
            navigationStore.selectedConsoleTab = .diagnostics
        case "show_session_tab":
            navigationStore.selectedConsoleTab = .session
        case "show_ai_runtime_tab":
            navigationStore.selectedConsoleTab = .aiRuntime

        // Workspace actions
        case "run_exercise":
            store.runSelectedExercise(processStore: processStore)
        case "run_tests":
            store.runSelectedExerciseTests(processStore: processStore)
        case "save_exercise":
            store.saveSelectedExercise()
        case "close_file":
            store.closeActiveTab()

        // Workspace management
        case "new_workspace":
            store.showNewWorkspacePrompt()
        case "import_exercises":
            store.openWorkspace()
        case "clone_repo":
            store.showCloneSheet()
        case "workspace_palette":
            store.hideCommandPalette()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                store.showWorkspacePalette()
            }
            return

        default:
            // Go-to-line commands: goto_50, goto_13, etc.
            if command.id.starts(with: "goto_"), let line = Int(command.id.replacingOccurrences(of: "goto_", with: "")) {
                store.goToLine(line)
            }
        }
        store.hideCommandPalette()
    }
}

// MARK: - Keyboard handler (Arrow keys, Ctrl+N/P, Tab)

private struct PaletteKeyboardHandler: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PaletteKeyView()
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onConfirm = onConfirm
        view.onDismiss = onDismiss
        // Start monitoring keyboard
        view.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? PaletteKeyView else { return }
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onConfirm = onConfirm
        view.onDismiss = onDismiss
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? PaletteKeyView)?.stopMonitoring()
    }
}

private final class PaletteKeyView: NSView {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onDismiss: (() -> Void)?
    private var monitor: Any?

    func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode

            // Arrow Down or Ctrl+N → move down
            if keyCode == 125 && modifiers.isEmpty { // Arrow Down
                self.onMoveDown?()
                return nil
            }
            if modifiers == .control, event.charactersIgnoringModifiers?.lowercased() == "n" {
                self.onMoveDown?()
                return nil
            }

            // Arrow Up or Ctrl+P → move up
            if keyCode == 126 && modifiers.isEmpty { // Arrow Up
                self.onMoveUp?()
                return nil
            }
            if modifiers == .control, event.charactersIgnoringModifiers?.lowercased() == "p" {
                self.onMoveUp?()
                return nil
            }

            // Tab → confirm selection
            if keyCode == 48 && modifiers.isEmpty { // Tab
                self.onConfirm?()
                return nil
            }

            // Escape → dismiss
            if keyCode == 53 && modifiers.isEmpty {
                self.onDismiss?()
                return nil
            }

            return event
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - Model

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcut: String?
    let keywords: [String]
}
