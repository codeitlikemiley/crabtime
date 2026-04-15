# Crab Time
> An AI-native IDE specifically tailored for learning Rust via community Rustlings challenges and Exercism.

Crab Time provides a focused context-rich environment that strips away the complexity of traditional IDEs. It replaces generic AI web chat with deeply integrated coding features designed *specifically* for Rust students:

- Real-time compiler diagnostics overlaid directly on your code
- Instant test feedback via an integrated `cargo runner` terminal experience
- Immediate side-by-side solutions via AI generated implementations
- Direct Exercism API integration for fetching and submitting assignments

![Crab Time](.github/preview.png)

## Installation

Crab Time requires **macOS 14.0+** and relies on system Rust dependencies.

1. Download the latest `.dmg` release from the [Releases](https://github.com/codeitlikemiley/crabtime/releases) page.
2. Drag `Crab Time.app` to your Applications folder.
3. On first launch, if you lack `rustc`, `cargo`, or the `exercism` CLI, Crab Time's Setup Wizard will automatically download and install these dependencies locally.

### Manual Building

If you wish to build Crab Time from source:

```bash
git clone https://github.com/codeitlikemiley/crabtime.git
cd crabtime/CrabTime
swift build -c release
```

The resulting app bundle will exist in `dist/` after running:

```bash
make publish
```

## Features
- **Integrated AI Chat**: Built-in support for Anthropic (Claude), OpenAI, and Gemini — grounded exclusively against your active workspace, current diagnostics, and exercise context.
- **AI-Verified Completion**: "Verify & Mark Done" compiles your code, runs it, and asks the AI for a PASS/FAIL verdict before marking an exercise as done.
- **ACP Session Reuse**: Gemini CLI and OpenCode run through ACP-backed warm sessions so the first load is cold, then follow-up turns reuse the same agent session.
- **Slash Commands**: `/verify`, `/challenge`, `/try-again` — trigger AI workflows directly from the chat composer.
- **Dependency Manager Wizard**: Installs Rust tooling seamlessly on startup for an out-of-the-box learning experience.
- **Exercism Integration**: One-click download of assignments and integrated submission straight from the editor.
- **CodeCrafters Integration**: Run `git push`-based submissions with remote CI feedback, directly from the Inspector.
- **Fast Native UI**: Built entirely in Swift/SwiftUI with AppKit-backed components for low-latency editing and terminal output.

## Architecture

For an in-depth look at how Crab Time manages state, processes, AI context, and terminal emulation, see [ARCHITECTURE.md](./ARCHITECTURE.md).

## License
MIT License.
