import Foundation
import AppKit

/// Protocol defining the interface for LLM services
protocol LLMServiceProtocol: Sendable {
    /// Analyze an image using vision model (qwen-vl-plus)
    /// - Parameters:
    ///   - image: The NSImage to analyze
    ///   - prompt: The text prompt to guide analysis
    /// - Returns: The analysis result as a string
    func analyzeImage(_ image: NSImage, prompt: String) async -> String?
    
    /// Generate text using the planning model (qwen-max)
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - systemPrompt: Optional system prompt for context
    /// - Returns: The generated text response
    func generateText(prompt: String, systemPrompt: String?) async -> String?
    
    /// Generate a task plan based on user goal and current screen state
    /// - Parameters:
    ///   - goal: The user's stated goal
    ///   - currentState: Description of the current screen state
    /// - Returns: Array of TaskStep objects representing the plan
    func generatePlan(goal: String, currentState: String) async -> [TaskStep]
}

/// Enum representing available Qwen models
enum QwenModel: String, Sendable {
    case visionPlus = "qwen-vl-plus"
    case max = "qwen-max"
}

/// Error types for LLM service operations
enum LLMServiceError: Error, Sendable {
    case networkError(String)
    case invalidResponse
    case imageEncodingFailed
    case maxRetriesExceeded
}
