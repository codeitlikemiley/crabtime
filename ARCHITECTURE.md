# Crab Time Architecture

Crab Time is constructed natively in Swift and SwiftUI, leveraging a reactive state architecture that bridges the gap between Apple's display frameworks and low-level CLI tooling commonly used in the Rust ecosystem.

## Core Concepts

### WorkspaceStore (State Management)
At the heart of Crab Time lies the `@MainActor` `WorkspaceStore`. It provides centralized state management for the entire application, functioning similarly to a Redux store but utilizing Swift's observation regime (`@Observable` / `@Published` equivalents in the Observation framework). 

It governs:
- **Navigation & Selection**: Which project node, tab, or layout (`leftSidebarTab`, `rightSidebarTab`) is active.
- **Process Emulation**: Managing references to active tasks such as `cargo runner run` or `cargo test`.
- **Keyboard Shortcuts**: Bridging global key commands (`cmd+shft+e`, `cmd+j`) to view models or state toggles.

### DependencyManager
Handles ambient CLI requirements by resolving universal `PATH` strings (integrating `~/.cargo/bin`, Homebrew locations, etc). The IDE leverages this manager on launch. If core utilities (like `cargo`, `rustc`, or `exercism`) are absent, it prompts an async download-and-install workflow before unblocking the main UI thread.

### Process Isolation & Terminal Emulation
Instead of bundling a complete terminal emulator like iTerm or alacritty, Crab Time captures raw stdout/stderr from decoupled `Process` elements.
- **CargoRunner**: Constructs targeted command-line operations (e.g. `cargo check --message-format short`). It maps structured output into `ExerciseCheck` models mapped to the Inspector overlay.
- **PTY System**: For certain interactive tasks, the app utilizes basic PTY creation to spoof an interactive TTY output so colors or terminal-specific rendering functions succeed in standard outputs.

### AI Integration
The app implements a flexible `AIProviderManager` resolving context via strategy implementations (like `ExerciseContextBuilder`). When a user asks an AI agent a question, the system bundles:
- The current open file.
- Active workspace structure.
- Present diagnostic outputs or compiler failures.

This deeply embeds prompt-engineering directly into the IDE workflow.

### ACP Session Transport
CLI-backed providers can now run through either the legacy one-shot command path or an ACP-backed persistent session path.

- **Transport toggle**: Each eligible CLI provider exposes a settings toggle between the current cold-start implementation and ACP.
- **Warm sessions**: ACP sessions persist the remote `sessionId` in `ExerciseChatSession.backendSessionID`, allowing later turns to reuse the same agent session instead of reinitializing the CLI every time.
- **Cross-client adapter model**: Native ACP clients such as Gemini CLI and OpenCode launch directly through their ACP entrypoints, while providers like Codex can be supported through ACP adapters such as `codex-acp`.
- **Debugging and logging**: Raw ACP traffic and agent stderr are written under `~/Library/Application Support/crab-time/logs/acp/`, and high-level session/tool-call events are surfaced in the existing Session console.
- **In-app runtime panel**: The Console now includes an `AI Runtime` tab that exposes the active provider, transport, auth state, warm session ID, ACP log location, and live tool-call updates.
- **Auth and permissions**: The ACP transport negotiates `initialize`, retries `authenticate` on auth-related failures, and handles `session/request_permission` by prompting the user through a native alert.
