import Foundation
import AppKit

/// V13: Simplified LLM Service Protocol - VLM analysis only
/// Removed: Step generation, TR-P-D methods
protocol LLMServiceProtocol: Sendable {
    
    /// Analyze an image with a text prompt
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - prompt: The text prompt describing what to analyze
    /// - Returns: The LLM's analysis as text
    func analyzeImage(_ image: NSImage, prompt: String) async -> String?
    
    /// Generate text based on a prompt
    /// - Parameters:
    ///   - prompt: The user prompt
    ///   - systemPrompt: Optional system prompt to guide the model
    /// - Returns: The generated text
    func generateText(prompt: String, systemPrompt: String?) async -> String?
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
    case apiError(String)
    case parsingFailed
}
