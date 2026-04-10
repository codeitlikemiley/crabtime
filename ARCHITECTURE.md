# RustGoblin Architecture

RustGoblin is constructed natively in Swift and SwiftUI, leveraging a reactive state architecture that bridges the gap between Apple's display frameworks and low-level CLI tooling commonly used in the Rust ecosystem.

## Core Concepts

### WorkspaceStore (State Management)
At the heart of RustGoblin lies the `@MainActor` `WorkspaceStore`. It provides centralized state management for the entire application, functioning similarly to a Redux store but utilizing Swift's observation regime (`@Observable` / `@Published` equivalents in the Observation framework). 

It governs:
- **Navigation & Selection**: Which project node, tab, or layout (`leftSidebarTab`, `rightSidebarTab`) is active.
- **Process Emulation**: Managing references to active tasks such as `cargo runner run` or `cargo test`.
- **Keyboard Shortcuts**: Bridging global key commands (`cmd+shft+e`, `cmd+j`) to view models or state toggles.

### DependencyManager
Handles ambient CLI requirements by resolving universal `PATH` strings (integrating `~/.cargo/bin`, Homebrew locations, etc). The IDE leverages this manager on launch. If core utilities (like `cargo`, `rustc`, or `exercism`) are absent, it prompts an async download-and-install workflow before unblocking the main UI thread.

### Process Isolation & Terminal Emulation
Instead of bundling a complete terminal emulator like iTerm or alacritty, RustGoblin captures raw stdout/stderr from decoupled `Process` elements.
- **CargoRunner**: Constructs targeted command-line operations (e.g. `cargo check --message-format short`). It maps structured output into `ExerciseCheck` models mapped to the Inspector overlay.
- **PTY System**: For certain interactive tasks, the app utilizes basic PTY creation to spoof an interactive TTY output so colors or terminal-specific rendering functions succeed in standard outputs.

### AI Integration
The app implements a flexible `AIProviderManager` resolving context via strategy implementations (like `ExerciseContextBuilder`). When a user asks an AI agent a question, the system bundles:
- The current open file.
- Active workspace structure.
- Present diagnostic outputs or compiler failures.

This deeply embeds prompt-engineering directly into the IDE workflow.
