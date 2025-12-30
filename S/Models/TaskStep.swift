import Foundation

/// Represents a single navigation step in the AI-guided task
struct TaskStep: Identifiable, Codable, Sendable {
    let id: UUID
    let instruction: String
    let expectedUIState: String?
    let isCompleted: Bool
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        instruction: String,
        expectedUIState: String? = nil,
        isCompleted: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.instruction = instruction
        self.expectedUIState = expectedUIState
        self.isCompleted = isCompleted
        self.timestamp = timestamp
    }
    
    func markCompleted() -> TaskStep {
        TaskStep(
            id: id,
            instruction: instruction,
            expectedUIState: expectedUIState,
            isCompleted: true,
            timestamp: timestamp
        )
    }
}
