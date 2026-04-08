# Architecture: RustGoblin 2.0

## System Shape
RustGoblin is currently implemented as a Swift package executable with a SwiftUI app entry point. The package is good for fast local iteration, but App Store shipping still requires a separate macOS app bundle target.

## UI Architecture
- `WorkspaceStore` is the single `@Observable` app state owner.
- `MainSplitView` composes a stable four-area workbench:
  - workspace sidebar
  - problem browser
  - editor workbench
  - inspector
- Each major pane is its own view type.
- Liquid Glass is applied at the pane level to keep the interface coherent and avoid ad hoc blur layers.

## Data Model
- `ExerciseWorkspace`
  - root import URL
  - workspace title
  - list of `ExerciseDocument`
- `ExerciseDocument`
  - source file URLs and loaded contents
  - parsed summary and checks
  - optional hint and solution assets
- `Diagnostic`
  - parsed compiler feedback
- `ProcessOutput`
  - stdout, stderr, exit status, and command metadata

## Import Pipeline
- `WorkspaceImporter` accepts either a Rust source file or a directory.
- For single-file imports:
  - use the file directly as the active source
- For directory imports:
  - detect whether the selected directory is itself an exercise
  - recursively discover nested exercise directories
  - build `ExerciseDocument` values from filesystem artifacts
- Source preference order:
  - `challenge.rs`
  - `src/main.rs`
  - `src/lib.rs`
  - first non-solution `.rs` file

## Execution Pipeline
- `WorkspaceStore` saves the editor draft before execution.
- `CargoRunner` chooses execution mode:
  - `cargo +nightly -Zscript <file>` for script exercises
  - `cargo test --color never` for Cargo projects
- `DiagnosticParser` extracts lightweight compiler diagnostics from stderr.

## Why The Layout Is Stable
- The old implementation relied on split-view behavior that could aggressively reclaim space and push content around.
- The rebuilt workbench uses explicit pane widths for support surfaces and leaves the editor as the flexible column.
- Hide/show behavior removes whole panes cleanly rather than rebalancing the entire interface unpredictably.

## Packaging Reality

### What Works Today
- `swift build`
- `swift test`
- `xcodebuild build`
- `xcodebuild archive`

### What The Current Archive Produces
- A universal binary installed under `usr/local/bin` inside the archive.
- Not an App Store-ready `.app` bundle.

### What Is Required For App Store Shipping
- A dedicated Xcode macOS app target that embeds these Swift sources.
- Code signing and notarization settings.
- Sandboxing entitlements.
- File access strategy for user-selected exercise folders.
- Export options for App Store Connect submission.

## Recommended Next Packaging Step
- Keep the package as the app’s core module for development.
- Add a thin Xcode app wrapper target for shipping.
- Move App Store-specific entitlements and signing settings into that wrapper instead of burying them inside the learning logic.
