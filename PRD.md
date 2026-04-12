# Product Requirements Document: Crab Time 2.0

## Product Vision
Crab Time is a native desktop Rust practice lab for people who want a tighter loop than a browser tab and less noise than a full IDE. The app should feel closer to HackerRank or LeetCode for local Rust exercises: import a folder, browse problems, edit code, run it locally, inspect output, and learn from hints without leaving the workspace.

## Core User
- Rust learners who want an offline challenge runner.
- Advanced Rust developers who practice kata-style exercises locally.
- Users maintaining folders of structured learning artifacts such as `README.md`, `hint.md`, `challenge.rs`, and `solution.rs`.

## Primary Jobs To Be Done
- Import a single Rust file, a challenge folder, or a workspace of many exercises.
- Read the brief and hints while editing the active solution.
- Run the current exercise with the local Rust toolchain and immediately see output and compiler feedback.
- Inspect the imported files and optionally preview the reference solution.

## Product Principles
- The editor must stay dominant; support panes should never push the coding area off-screen.
- Importing content must be dead simple.
- Feedback must be local, fast, and legible.
- The UI should look intentional and modern, not like a generic split-view demo.

## Experience Layout

### 1. Left Sidebar
- Persistent workspace sidebar for import, save, run, and layout toggles.
- Shows the currently loaded workspace path and active file context.

### 2. Problem Browser
- Searchable exercise browser.
- Selecting an exercise updates the active brief and editor.
- Lower area renders the problem statement from `README.md`.

### 3. Editor Workbench
- Top: code editor for the active Rust source file.
- Bottom: feedback console with Output, Diagnostics, and Session history tabs.
- Running an exercise automatically saves the draft first.

### 4. Right Inspector
- Hints from `hint.md`.
- Checklist extracted from assertions or test-like functions.
- Imported file manifest.
- Optional preview of `solution.rs`.

## Import Requirements
- Accept a direct `.rs` file import.
- Accept a single challenge directory.
- Accept a larger workspace folder and discover nested exercises automatically.
- Prefer `challenge.rs` when present.
- Fall back to `src/main.rs`, `src/lib.rs`, or the first runnable `.rs` source file.

## Runtime Requirements
- Use the user’s local Rust toolchain.
- Run `cargo +nightly -Zscript` for script-style exercises.
- Run `cargo test` for Cargo workspaces.
- Capture stdout, stderr, exit status, and lightweight diagnostics.

## Quality Bar
- Pane toggles animate cleanly and preserve editor usability.
- The UI remains legible at common laptop sizes without controls collapsing.
- Saving and running should never feel ambiguous.
- Missing artifacts degrade gracefully.

## Distribution Strategy

### Current Phase
- Ship as a local development app/package for fast iteration.
- Support `swift build`, `swift test`, `xcodebuild build`, and `xcodebuild archive`.

### App Store Phase
- The current Swift package archives a universal binary, not a sandboxed `.app` bundle suitable for App Store Connect.
- To ship to the Mac App Store, wrap the existing sources in a dedicated macOS app target and add signing, entitlements, sandboxing, and export configuration.

## Success Criteria
- A user can import a folder of Rust exercises and immediately browse them.
- Sidebar toggles never shove the editor off-screen.
- Running the active exercise shows output and diagnostics in one place.
- Hints and solution previews stay available without leaving the coding context.
