# Crab Time
> An AI-native IDE specifically tailored for learning Rust via community Rustlings challenges and Exercism.

Crab Time provides a focused context-rich environment that strips away the complexity of traditional IDEs. It replaces generic AI web chat with deeply integrated coding features designed *specifically* for Rust students: 

- Real-time compiler diagnostics overlaid directly on your code
- Instant test feedback via an integrated `cargo runner` terminal experience
- Immediate side-by-side solutions via AI generated implementations
- Direct Exercism API integration for fetching and submitting assignments.

![Crab Time](.github/preview.png)

## Installation

Crab Time requires **macOS 14.0+** and relies on system Rust dependencies. 

1. Download the latest `.dmg` release from the [Releases](https://github.com/goldcoders/rustgoblin/releases) page.
2. Drag `Crab Time.app` to your Applications folder.
3. On first launch, if you lack `rustc`, `cargo`, or the `exercism` CLI, Crab Time's Setup Wizard will automatically download and install these dependencies locally.

### Manual Building

If you wish to build Crab Time from source:

```bash
git clone https://github.com/goldcoders/rustgoblin.git
cd rustgoblin
make publish
```

The resulting `Crab Time.app` bundle will exist in `dist/`.

To install the published app bundle locally:

```bash
make install
```

## Features
- **Integrated AI Chat**: Built-in support for Anthropic (Claude 3.5 Sonnet) and OpenAI, grounded exclusively against your active workspace, current diagnostics, and task domain context.
- **ACP Session Reuse**: Gemini CLI and OpenCode can run through ACP-backed warm sessions so the first load is cold, then follow-up turns reuse the same agent session.
- **Dependency Manager Wizard**: Installs Rust tooling seamlessly on startup for an out-of-the-box learning experience.
- **Exercism integration**: One-click download of assignments, and integrated submission straight from the editor.
- **Fast UI**: Built entirely in native Swift/AppKit overlaying a highly robust source editor framework.

## Roadmap & Known Issues
Currently, Crab Time is focused primarily on the macOS experience given its AppKit foundations. To learn more about its internals and how we manage processes, state, and terminal emulation, read the architecture documentation.

## License
MIT License.
