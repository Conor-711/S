import Foundation

/// Maintains the execution history and context for the current AI session
struct SessionContext: Sendable {
    let sessionId: UUID
    let startTime: Date
    var steps: [TaskStep]
    var userGoal: String
    var conversationHistory: [ConversationMessage]
    
    init(
        sessionId: UUID = UUID(),
        startTime: Date = Date(),
        steps: [TaskStep] = [],
        userGoal: String = "",
        conversationHistory: [ConversationMessage] = []
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.steps = steps
        self.userGoal = userGoal
        self.conversationHistory = conversationHistory
    }
    
    mutating func addStep(_ step: TaskStep) {
        steps.append(step)
    }
    
    mutating func addMessage(_ message: ConversationMessage) {
        conversationHistory.append(message)
    }
    
    var completedStepsCount: Int {
        steps.filter { $0.isCompleted }.count
    }
    
    var currentStep: TaskStep? {
        steps.first { !$0.isCompleted }
    }
}

/// Represents a message in the conversation history
struct ConversationMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}
