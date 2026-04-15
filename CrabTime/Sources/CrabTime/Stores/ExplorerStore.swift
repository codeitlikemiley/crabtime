import Foundation
import Observation

@Observable
@MainActor
final class ExplorerStore {
    var selectedFileURL: URL?
    var selectedNodePath: String?
    var openTabs: [ActiveDocumentTab] = []
    
    var previewText: String = ""
    var searchText: String = ""
    
    var searchFocusToken: Int = 0
    var isKeyboardFocusActive: Bool = false
    
    var expandedDirectoryPaths: Set<String> = []
    
    init() {}
}
