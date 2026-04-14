import Foundation

enum ChatSlashCommandResult {
    /// Command resolved locally. The string is presented as the AI's reply without going to network.
    case localReply(String)
    
    /// Command rewrites the original user prompt with this payload.
    /// Normal AI generation proceeds sending this new prompt to the backend.
    case rewritePrompt(String)
}
