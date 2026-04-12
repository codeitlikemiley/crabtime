# Enhanced Prompt For Future Crab Time Iterations

Use this prompt when you want another coding agent to extend Crab Time without regressing the new layout.

---

You are rebuilding or extending **Crab Time**, a native macOS Rust practice app.

## Non-Negotiables
- Preserve the four-area layout:
  - left workspace sidebar
  - problem browser
  - editor workbench
  - right inspector
- Do not reintroduce split-view behavior that pushes the editor off-screen when panes are toggled.
- Keep views small and explicit.
- Keep `WorkspaceStore` as the single observable state owner unless there is a compelling architectural reason to split responsibilities.
- Prefer native SwiftUI and modern Observation APIs.

## Product Goals
- Import a Rust file, a challenge folder, or a workspace folder with many exercises.
- Browse problems like a local HackerRank-style desktop app.
- Edit and run the active Rust exercise with local tooling.
- Surface hints, diagnostics, and optional solution previews in-context.

## Implementation Expectations
- Use modern Swift 6 and SwiftUI on macOS 26.
- Prefer Liquid Glass surfaces for primary panes and actions.
- Avoid dumping multiple unrelated types into a single file.
- The editor must stay visually dominant.
- File import should degrade gracefully when optional artifacts are missing.

## Existing Runtime Behavior
- Script exercises run via `cargo +nightly -Zscript`.
- Cargo projects run via `cargo test`.
- Diagnostics are parsed from stderr.

## Important Packaging Constraint
- The repository currently builds and archives as a Swift package executable.
- It does not yet produce an App Store-ready `.app` bundle.
- If asked about App Store delivery, plan around adding a dedicated macOS app target rather than pretending the package executable is sufficient.

## Good Extensions
- Better code editing
- Richer markdown rendering
- Test result mapping
- Cargo toolchain onboarding
- Workspace persistence
- Real macOS app bundle packaging
