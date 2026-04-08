import AppKit
import SwiftUI

final class RustGoblinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct RustGoblinApp: App {
    @NSApplicationDelegateAdaptor(RustGoblinAppDelegate.self) private var appDelegate
    @State private var workspaceStore = WorkspaceStore()

    var body: some Scene {
        WindowGroup("RustGoblin") {
            MainSplitView()
                .environment(workspaceStore)
                .frame(minWidth: 1360, minHeight: 860)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1640, height: 980)
        .commands {
            CommandMenu("Workspace") {
                Button("Import Exercises…", action: workspaceStore.openWorkspace)
                    .keyboardShortcut("o", modifiers: .command)

                Button("Clone Repository…", action: workspaceStore.showCloneSheet)
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Download Exercism Exercise…", action: workspaceStore.showExercismDownloadPrompt)
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Check Exercism Setup", action: workspaceStore.showExercismStatus)
                    .keyboardShortcut("e", modifiers: [.command, .option])

                Button("Save Exercise", action: workspaceStore.saveSelectedExercise)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!workspaceStore.hasSelection)

                Button("Run Exercise", action: workspaceStore.runSelectedExercise)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!workspaceStore.hasSelection || workspaceStore.isRunning)

                Button("Submit to Exercism", action: workspaceStore.submitSelectedExerciseToExercism)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!workspaceStore.canSubmitSelectedExerciseToExercism)
            }

            CommandGroup(replacing: .sidebar) {
                Button(
                    workspaceStore.showsProblemPane ? "Hide Problems" : "Show Problems",
                    action: workspaceStore.toggleProblemPaneVisibility
                )
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button(
                    workspaceStore.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                    action: workspaceStore.toggleInspector
                )
                .keyboardShortcut("2", modifiers: [.command, .option])
            }
        }
    }
}
