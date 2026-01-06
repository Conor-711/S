import Foundation

/// V9: Visual Note for the Knowledge Base feature
/// Stores text metadata only - images are ephemeral and not saved to disk
struct VisualNote: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let caption: String      // Brief description of the content
    let intent: String       // Why the user saved this
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        caption: String,
        intent: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.caption = caption
        self.intent = intent
    }
}

/// VLM Analysis response structure for visual note capture
struct VisualNoteAnalysis: Codable {
    let caption: String
    let intent: String
}
