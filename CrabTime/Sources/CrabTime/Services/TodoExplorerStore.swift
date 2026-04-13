import Foundation
import Observation

@Observable
@MainActor
final class TodoExplorerStore {
    var todoItems: [TodoItem] = []
    var todoSearchText: String = ""
    var todoScopeCurrentFile: Bool = false
    var selectedTodoIndex: Int = 0

    @ObservationIgnored private let todoScanner = TodoScanner()

    func visibleTodoItems(using store: WorkspaceStore) -> [TodoItem] {
        var items = todoItems

        // Scope filter: current file only
        if todoScopeCurrentFile,
           let currentPath = store.selectedExplorerFileURL?.standardizedFileURL.path,
           let rootPath = store.workspace?.rootURL.standardizedFileURL.path {
            let relativePath = currentPath.hasPrefix(rootPath + "/")
                ? String(currentPath.dropFirst(rootPath.count + 1))
                : currentPath
            items = items.filter { $0.filePath == relativePath }
        }

        // Text search
        if !todoSearchText.isEmpty {
            let query = todoSearchText.lowercased()
            items = items.filter {
                $0.text.lowercased().contains(query) ||
                $0.fileName.lowercased().contains(query) ||
                $0.kind.label.lowercased().contains(query)
            }
        }

        return items
    }

    func refreshTodoItems(using store: WorkspaceStore) {
        guard let rootURL = store.workspace?.rootURL else {
            todoItems = []
            return
        }
        todoItems = todoScanner.scanWorkspace(rootURL: rootURL)
        selectedTodoIndex = 0
    }

    func moveTodoSelectionUp(using store: WorkspaceStore) {
        guard !visibleTodoItems(using: store).isEmpty else { return }
        selectedTodoIndex = max(selectedTodoIndex - 1, 0)
    }

    func moveTodoSelectionDown(using store: WorkspaceStore) {
        let items = visibleTodoItems(using: store)
        guard !items.isEmpty else { return }
        selectedTodoIndex = min(selectedTodoIndex + 1, items.count - 1)
    }

    func activateSelectedTodo(using store: WorkspaceStore) {
        let items = visibleTodoItems(using: store)
        guard items.indices.contains(selectedTodoIndex) else { return }
        activateTodoItem(items[selectedTodoIndex], using: store)
    }

    func activateTodoItem(_ item: TodoItem, using store: WorkspaceStore) {
        guard let rootURL = store.workspace?.rootURL else { return }
        let fileURL = rootURL.appendingPathComponent(item.filePath)

        // Ensure the file is opened and focused
        store.activateDocument(at: fileURL, persistState: true)

        // Go to the line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak store] in
            store?.goToLine(item.line)
        }
    }
}
