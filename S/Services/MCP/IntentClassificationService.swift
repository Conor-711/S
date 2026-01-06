import Foundation
import AppKit

// MARK: - Intent Classification Service
// Uses VLM to classify screenshot intent for MCP routing

@MainActor
final class IntentClassificationService: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let llmService: GeminiLLMService
    
    // MARK: - Initialization
    
    init(llmService: GeminiLLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Classification
    
    /// Classify screenshot intent using VLM
    func classifyIntent(context: SnapshotContext) async throws -> VLMAnalysisResult {
        print("🧠 [IntentClassifier] Analyzing screenshot...")
        
        let prompt = buildClassificationPrompt(context: context)
        
        guard let response = await llmService.analyzeImage(context.image, prompt: prompt) else {
            throw ConnectorError.vlmParsingFailed
        }
        
        print("🧠 [IntentClassifier] Raw response: \(response.prefix(500))...")
        
        return try parseVLMResponse(response)
    }
    
    // MARK: - Prompt Building
    
    private func buildClassificationPrompt(context: SnapshotContext) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        return """
        [SYSTEM]
        You are a semantic router for a macOS productivity tool. Analyze the provided image and metadata.
        Classify the user's intent into ONE of these categories:
        
        - calendar: Contains dates, times, Zoom/Meet links, or chat about scheduling meetings.
        - notion: Contains text-heavy content, articles, documentation, code snippets, or generic notes.
        - linear: Contains software error messages (red text, stack traces), bug reports, or broken UI.
        - design: Contains beautiful UI screenshots, color palettes, or visual inspiration.
        
        [RULES]
        1. If the intent is "linear" or "design", set requires_image_upload to true.
        2. Extract key fields: title (short), description (detailed).
        3. For "calendar", try to extract detected_time if visible.
        4. If intent is ambiguous, provide a secondary_intent with lower confidence.
        5. Confidence score: 0.0-1.0 (how certain you are).
        
        [CONTEXT]
        Browser URL: \(context.browserURL?.absoluteString ?? "None")
        Current Time: \(dateFormatter.string(from: context.timestamp))
        
        [OUTPUT FORMAT]
        Return ONLY valid JSON, no markdown fences:
        {
          "primary_intent": "notion|calendar|linear|design|unknown",
          "secondary_intent": null or "notion|calendar|linear|design",
          "confidence_score": 0.85,
          "title": "Short descriptive title",
          "description": "Detailed description of the content",
          "detected_time": null or "ISO8601 date string if calendar intent",
          "requires_image_upload": false,
          "suggested_action_payload": {
            "title": "Same as title",
            "content": "Markdown formatted content for the action"
          }
        }
        """
    }
    
    // MARK: - Response Parsing
    
    private func parseVLMResponse(_ response: String) throws -> VLMAnalysisResult {
        // Clean response: remove markdown fences if present
        var cleanedResponse = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ```json and ``` markers
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = String(cleanedResponse.dropFirst(7))
        } else if cleanedResponse.hasPrefix("```") {
            cleanedResponse = String(cleanedResponse.dropFirst(3))
        }
        
        if cleanedResponse.hasSuffix("```") {
            cleanedResponse = String(cleanedResponse.dropLast(3))
        }
        
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            print("❌ [IntentClassifier] Failed to convert response to data")
            throw ConnectorError.vlmParsingFailed
        }
        
        do {
            // First try direct decoding
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(VLMAnalysisResult.self, from: data)
        } catch {
            print("❌ [IntentClassifier] JSON decode error: \(error)")
            
            // Fallback: try manual parsing
            return try parseManually(cleanedResponse)
        }
    }
    
    private func parseManually(_ json: String) throws -> VLMAnalysisResult {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectorError.vlmParsingFailed
        }
        
        // Parse primary intent
        let primaryIntentString = dict["primary_intent"] as? String ?? "unknown"
        let primaryIntent = IntentCategory(rawValue: primaryIntentString) ?? .unknown
        
        // Parse secondary intent
        var secondaryIntent: IntentCategory? = nil
        if let secondaryString = dict["secondary_intent"] as? String {
            secondaryIntent = IntentCategory(rawValue: secondaryString)
        }
        
        // Parse confidence
        let confidence = dict["confidence_score"] as? Double ?? 0.5
        
        // Parse semantic fields
        let title = dict["title"] as? String
        let description = dict["description"] as? String
        
        // Parse detected time
        var detectedTime: Date? = nil
        if let timeString = dict["detected_time"] as? String {
            let formatter = ISO8601DateFormatter()
            detectedTime = formatter.date(from: timeString)
        }
        
        // Parse requires image upload
        let requiresImageUpload = dict["requires_image_upload"] as? Bool ?? false
        
        // Parse suggested action payload
        var suggestedPayload: [String: String] = [:]
        if let payload = dict["suggested_action_payload"] as? [String: Any] {
            for (key, value) in payload {
                if let stringValue = value as? String {
                    suggestedPayload[key] = stringValue
                }
            }
        }
        
        // Ensure payload has at least title and content
        if suggestedPayload["title"] == nil, let t = title {
            suggestedPayload["title"] = t
        }
        if suggestedPayload["content"] == nil, let d = description {
            suggestedPayload["content"] = d
        }
        
        return VLMAnalysisResult(
            primaryIntent: primaryIntent,
            secondaryIntent: secondaryIntent,
            confidenceScore: confidence,
            title: title,
            description: description,
            detectedTime: detectedTime,
            requiresImageUpload: requiresImageUpload,
            suggestedActionPayload: suggestedPayload
        )
    }
}

// MARK: - Quick Classification (Lightweight)

extension IntentClassificationService {
    
    /// Quick classification without full semantic extraction
    func quickClassify(image: NSImage) async -> IntentCategory {
        let quickPrompt = """
        Classify this screenshot into ONE category:
        - calendar (dates, meetings, schedules)
        - notion (text, articles, notes, code)
        - linear (errors, bugs, crashes)
        - design (UI, visual inspiration)
        - unknown (unclear)
        
        Reply with ONLY the category name, nothing else.
        """
        
        guard let response = await llmService.analyzeImage(image, prompt: quickPrompt) else {
            return .unknown
        }
        
        let category = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return IntentCategory(rawValue: category) ?? .unknown
    }
}
