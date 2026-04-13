import SwiftUI
import Observation

@Observable
@MainActor
final class NavigationStore {

    
    
    func toggleLeftColumnVisibility() {
        contentDisplayMode = contentDisplayMode == .editorMaximized ? .split : .editorMaximized
    }

    func toggleTerminalVisibility() {
        if terminalDisplayMode == .hidden {
            terminalDisplayMode = .split
        } else {
            terminalDisplayMode = .hidden
        }
    }

    func toggleTerminalMaximize() {
        terminalDisplayMode = terminalDisplayMode == .maximized ? .split : .maximized
    }
    
    func toggleInspector() {
        isInspectorVisible.toggle()
    }
    
    func toggleRightSidebarVisibility() {
        toggleInspector()
    }
    var terminalDisplayMode: TerminalDisplayMode = .split
    var selectedConsoleTab: ConsoleTab = .output
    var isInspectorVisible: Bool = true
    var showWorkspaceDialog: Bool = false

    var contentDisplayMode: ContentDisplayMode = .split
    var editorDisplayMode: EditorDisplayMode = .edit

    
    var showsEditorPane: Bool {
        contentDisplayMode != .problemMaximized
    }

    var showsProblemPane: Bool {
        contentDisplayMode != .editorMaximized
    }

    var canToggleDiffMode: Bool {
        editorDisplayMode == .edit || editorDisplayMode == .diff
    }

    
    var isShowingDiffPreview: Bool {
        editorDisplayMode == .diff
    }

    var showsInspector: Bool {
        contentDisplayMode != .problemMaximized && isInspectorVisible
    }

    var showsTerminal: Bool {
        terminalDisplayMode != .hidden
    }

    var isTerminalMaximized: Bool {
        terminalDisplayMode == .maximized
    }
    
    var sidebarMode: SidebarMode = .exercises
}
