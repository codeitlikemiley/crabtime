import Foundation
import Observation

@Observable
@MainActor
final class EditorStateStore {
    var text: String = ""
    var isDirty: Bool = false
    var cursorLine: Int = 1
    
    /// Current cursor byte offset in the active text view, updated on every selection change.
    /// Always reflects the last known good position regardless of first-responder state.
    var cursorOffset: Int = 0
    
    /// Per-file cursor offset (NSRange.location) keyed by standardized file path.
    var cursorPositionByPath: [String: Int] = [:]
    
    /// Token to trigger cursor restoration after tab switch.
    var restoreCursorToken: Int = 0
    
    /// The cursor offset to restore when switching tabs.
    var restoreCursorOffset: Int? = nil
    
    // Non-observed state
    @ObservationIgnored var draftTextByPath: [String: String] = [:]
    
    init() {}
}
