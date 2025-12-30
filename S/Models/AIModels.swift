import Foundation

// MARK: - Meso Goal (Milestone)

/// Represents a medium-level goal/milestone in the task plan
struct MesoGoal: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let description: String
    var isCompleted: Bool
    var completedActions: [String]
    
    init(id: Int, title: String, description: String, isCompleted: Bool = false, completedActions: [String] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.isCompleted = isCompleted
        self.completedActions = completedActions
    }
    
    func markCompleted() -> MesoGoal {
        var copy = self
        copy.isCompleted = true
        return copy
    }
}

// MARK: - Micro Instruction

/// Represents the next immediate step to execute
struct MicroInstruction: Codable, Sendable {
    let instruction: String
    let successCriteria: String
    let memoryToSave: [String: String]?
    let valueToCopy: String?
    
    enum CodingKeys: String, CodingKey {
        case instruction
        case successCriteria = "success_criteria"
        case memoryToSave = "memory_to_save"
        case valueToCopy = "value_to_copy"
    }
    
    init(instruction: String, successCriteria: String, memoryToSave: [String: String]? = nil, valueToCopy: String? = nil) {
        self.instruction = instruction
        self.successCriteria = successCriteria
        self.memoryToSave = memoryToSave
        self.valueToCopy = valueToCopy
    }
}

// MARK: - Watcher Result

/// Result from the Watcher checking if criteria is met
struct WatcherResult: Codable, Sendable {
    let isComplete: Bool
    let reasoning: String
    
    enum CodingKeys: String, CodingKey {
        case isComplete = "is_complete"
        case reasoning
    }
}

// MARK: - Planner Response

/// Response structure from the Planner
struct PlannerResponse: Codable, Sendable {
    let goals: [MesoGoal]
}

// MARK: - Agent Session Context

/// Maintains the execution context for the AI agent
struct AgentSessionContext: Sendable {
    let sessionId: UUID
    let startTime: Date
    var userGoal: String
    var historySummary: [String]
    var blackboard: [String: String]
    var currentMesoGoals: [MesoGoal]
    var currentMesoIndex: Int
    var currentInstruction: MicroInstruction?
    var completedMesoCount: Int
    
    init(
        sessionId: UUID = UUID(),
        startTime: Date = Date(),
        userGoal: String = "",
        historySummary: [String] = [],
        blackboard: [String: String] = [:],
        currentMesoGoals: [MesoGoal] = [],
        currentMesoIndex: Int = 0,
        currentInstruction: MicroInstruction? = nil,
        completedMesoCount: Int = 0
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.userGoal = userGoal
        self.historySummary = historySummary
        self.blackboard = blackboard
        self.currentMesoGoals = currentMesoGoals
        self.currentMesoIndex = currentMesoIndex
        self.currentInstruction = currentInstruction
        self.completedMesoCount = completedMesoCount
    }
    
    var currentMesoGoal: MesoGoal? {
        guard currentMesoIndex < currentMesoGoals.count else { return nil }
        return currentMesoGoals[currentMesoIndex]
    }
    
    var hasMoreMesoGoals: Bool {
        return currentMesoIndex < currentMesoGoals.count
    }
    
    mutating func addToHistory(_ summary: String) {
        historySummary.append(summary)
        if historySummary.count > 10 {
            historySummary.removeFirst()
        }
    }
    
    mutating func updateBlackboard(_ newEntries: [String: String]) {
        for (key, value) in newEntries {
            blackboard[key] = value
        }
    }
    
    mutating func advanceToNextMeso() {
        if currentMesoIndex < currentMesoGoals.count {
            currentMesoGoals[currentMesoIndex] = currentMesoGoals[currentMesoIndex].markCompleted()
            completedMesoCount += 1
        }
        currentMesoIndex += 1
        currentInstruction = nil
    }
    
    var formattedHistory: String {
        if historySummary.isEmpty {
            return "No previous actions."
        }
        return historySummary.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
    
    var formattedBlackboard: String {
        if blackboard.isEmpty {
            return "Empty"
        }
        return blackboard.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
    
    /// Reset the session context to initial state
    mutating func reset() {
        userGoal = ""
        historySummary = []
        blackboard = [:]
        currentMesoGoals = []
        currentMesoIndex = 0
        currentInstruction = nil
        completedMesoCount = 0
    }
}

// MARK: - DashScope API Structures

/// Request structure for DashScope multimodal API
struct DashScopeRequest: Codable {
    let model: String
    let input: DashScopeInput
    
    struct DashScopeInput: Codable {
        let messages: [DashScopeMessage]
    }
}

struct DashScopeMessage: Codable {
    let role: String
    let content: [DashScopeContent]
}

enum DashScopeContent: Codable {
    case text(String)
    case imageUrl(String)
    
    enum CodingKeys: String, CodingKey {
        case text
        case image
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .text) {
            self = .text(text)
        } else if let image = try? container.decode(String.self, forKey: .image) {
            self = .imageUrl(image)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid content"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .imageUrl(let url):
            try container.encode(url, forKey: .image)
        }
    }
}

/// Response structure from DashScope API
struct DashScopeResponse: Codable {
    let output: DashScopeOutput?
    let requestId: String?
    let code: String?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case output
        case requestId = "request_id"
        case code
        case message
    }
    
    struct DashScopeOutput: Codable {
        let text: String?
        let choices: [DashScopeChoice]?
    }
    
    struct DashScopeChoice: Codable {
        let message: DashScopeChoiceMessage?
    }
    
    struct DashScopeChoiceMessage: Codable {
        let content: String?
    }
    
    var extractedText: String? {
        if let text = output?.text {
            return text
        }
        if let choices = output?.choices,
           let first = choices.first,
           let content = first.message?.content {
            return content
        }
        return nil
    }
}
