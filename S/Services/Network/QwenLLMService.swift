import Foundation
import AppKit

/// Implementation of LLMServiceProtocol using Alibaba DashScope API
final class QwenLLMService: LLMServiceProtocol, @unchecked Sendable {
    private let apiKey: String
    private let visionURL = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    private let textURL = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    private let maxRetries = 2  // Phase 2: Only 2 retries as per spec
    
    init(apiKey: String = Secrets.qwenAPIKey) {
        self.apiKey = apiKey
    }
    
    // MARK: - LLMServiceProtocol Implementation
    
    func analyzeImage(_ image: NSImage, prompt: String) async -> String? {
        guard let base64Image = encodeImageToBase64(image) else {
            print("Error: Failed to encode image to base64")
            return nil
        }
        
        let requestBody = buildVisionRequest(base64Image: base64Image, prompt: prompt)
        return await performRequestWithRetry(url: visionURL, body: requestBody)
    }
    
    func generateText(prompt: String, systemPrompt: String?) async -> String? {
        let requestBody = buildTextRequest(prompt: prompt, systemPrompt: systemPrompt)
        return await performRequestWithRetry(url: textURL, body: requestBody)
    }
    
    func generatePlan(goal: String, currentState: String) async -> [TaskStep] {
        let systemPrompt = """
        You are an AI assistant that helps users navigate macOS applications.
        Based on the user's goal and current screen state, generate a step-by-step plan.
        Each step should be a clear, actionable instruction.
        Return the steps as a JSON array with format: [{"instruction": "step text"}]
        """
        
        let prompt = """
        User Goal: \(goal)
        Current Screen State: \(currentState)
        
        Generate a step-by-step plan to achieve this goal.
        """
        
        guard let response = await generateText(prompt: prompt, systemPrompt: systemPrompt) else {
            return []
        }
        
        return parseStepsFromResponse(response)
    }
    
    // MARK: - Private Methods
    
    private func encodeImageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
    
    private func buildVisionRequest(base64Image: String, prompt: String) -> [String: Any] {
        return [
            "model": QwenModel.visionPlus.rawValue,
            "input": [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["image": "data:image/png;base64,\(base64Image)"],
                            ["text": prompt]
                        ]
                    ]
                ]
            ]
        ]
    }
    
    private func buildTextRequest(prompt: String, systemPrompt: String?) -> [String: Any] {
        var messages: [[String: String]] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])
        
        return [
            "model": QwenModel.max.rawValue,
            "input": [
                "messages": messages
            ]
        ]
    }
    
    private func performRequestWithRetry(url: String, body: [String: Any]) async -> String? {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let result = try await performRequest(url: url, body: body)
                return result
            } catch {
                lastError = error
                print("Request attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        
        print("Error: Network request failed after \(maxRetries) retries. Last error: \(lastError?.localizedDescription ?? "Unknown")")
        return nil
    }
    
    private func performRequest(url: String, body: [String: Any]) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw LLMServiceError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.qwenAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug: Print raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("API Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.networkError("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMServiceError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMServiceError.invalidResponse
        }
        
        // DashScope API response format varies by endpoint
        // Text generation: output.text or output.choices[].message.content (string)
        // Vision: output.choices[].message.content (array of {text: "..."})
        
        if let output = json["output"] as? [String: Any] {
            // Try direct text field first (qwen-max format)
            if let text = output["text"] as? String {
                return text
            }
            
            // Try choices array
            if let choices = output["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any] {
                
                // Vision API: content is array of objects with "text" field
                if let contentArray = message["content"] as? [[String: Any]],
                   let firstContent = contentArray.first,
                   let text = firstContent["text"] as? String {
                    return text
                }
                
                // Text API: content is a string
                if let content = message["content"] as? String {
                    return content
                }
            }
        }
        
        print("Unexpected response format: \(json)")
        throw LLMServiceError.invalidResponse
    }
    
    private func parseStepsFromResponse(_ response: String) -> [TaskStep] {
        guard let data = response.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return [TaskStep(instruction: response)]
        }
        
        return jsonArray.compactMap { dict in
            guard let instruction = dict["instruction"] else { return nil }
            return TaskStep(instruction: instruction)
        }
    }
    
    // MARK: - Phase 2: Agent Methods
    
    /// Send a request to the Planner to generate Meso Goals
    /// - Parameters:
    ///   - goal: User's stated goal
    ///   - history: Summary of completed actions
    ///   - image: Current screenshot
    /// - Returns: Array of MesoGoal milestones
    func sendPlannerRequest(goal: String, history: String, image: NSImage) async throws -> [MesoGoal] {
        print("🧠 [Planner] Generating plan for goal: \(goal)")
        
        guard let base64Image = encodeImageToBase64(image) else {
            throw LLMServiceError.imageEncodingFailed
        }
        
        let prompt = AgentPrompts.plannerPrompt(goal: goal, history: history)
        let requestBody = buildVisionRequest(base64Image: base64Image, prompt: prompt)
        
        guard let response = await performRequestWithRetry(url: visionURL, body: requestBody) else {
            throw LLMServiceError.maxRetriesExceeded
        }
        
        print("🧠 [Planner] Raw response: \(response)")
        
        // Parse the JSON response
        let goals = try parsePlannerResponse(response)
        print("🧠 [Planner] Parsed \(goals.count) meso goals")
        return goals
    }
    
    /// Send a request to the Navigator to get next instruction
    /// - Parameters:
    ///   - meso: Current milestone being worked on
    ///   - image: Current screenshot
    ///   - blackboard: Key-value store of extracted info
    /// - Returns: MicroInstruction with next step
    func sendNavigatorRequest(meso: MesoGoal, image: NSImage, blackboard: [String: String]) async throws -> MicroInstruction {
        print("🧭 [Navigator] Getting next step for: \(meso.title)")
        
        guard let base64Image = encodeImageToBase64(image) else {
            throw LLMServiceError.imageEncodingFailed
        }
        
        let blackboardStr = blackboard.isEmpty ? "Empty" : blackboard.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        let prompt = AgentPrompts.navigatorPrompt(mesoGoal: meso, blackboard: blackboardStr)
        let requestBody = buildVisionRequest(base64Image: base64Image, prompt: prompt)
        
        guard let response = await performRequestWithRetry(url: visionURL, body: requestBody) else {
            throw LLMServiceError.maxRetriesExceeded
        }
        
        print("🧭 [Navigator] Raw response: \(response)")
        
        let instruction = try parseNavigatorResponse(response)
        print("🧭 [Navigator] Instruction: \(instruction.instruction)")
        return instruction
    }
    
    /// Send a request to the Watcher to check if criteria is met
    /// - Parameters:
    ///   - criteria: Success criteria to check
    ///   - image: Current screenshot
    /// - Returns: Boolean indicating if criteria is met
    func sendWatcherRequest(criteria: String, image: NSImage) async throws -> Bool {
        print("👁️ [Watcher] Checking criteria: \(criteria)")
        
        guard let base64Image = encodeImageToBase64(image) else {
            throw LLMServiceError.imageEncodingFailed
        }
        
        let prompt = AgentPrompts.watcherPrompt(criteria: criteria)
        let requestBody = buildVisionRequest(base64Image: base64Image, prompt: prompt)
        
        guard let response = await performRequestWithRetry(url: visionURL, body: requestBody) else {
            throw LLMServiceError.maxRetriesExceeded
        }
        
        print("👁️ [Watcher] Raw response: \(response)")
        
        let result = try parseWatcherResponse(response)
        print("👁️ [Watcher] Is complete: \(result.isComplete), Reasoning: \(result.reasoning)")
        return result.isComplete
    }
    
    /// Send a request to summarize a completed milestone
    /// - Parameters:
    ///   - completedMeso: The milestone that was completed
    ///   - actions: Actions taken to complete it
    /// - Returns: Summary string for history
    func sendSummarizerRequest(completedMeso: MesoGoal, actions: [String]) async throws -> String {
        print("📝 [Summarizer] Summarizing: \(completedMeso.title)")
        
        let prompt = AgentPrompts.summarizerPrompt(mesoGoal: completedMeso, actions: actions)
        let requestBody = buildTextRequest(prompt: prompt, systemPrompt: nil)
        
        guard let response = await performRequestWithRetry(url: textURL, body: requestBody) else {
            throw LLMServiceError.maxRetriesExceeded
        }
        
        print("📝 [Summarizer] Summary: \(response)")
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Phase 2: Response Parsers
    
    private func parsePlannerResponse(_ response: String) throws -> [MesoGoal] {
        let cleanedResponse = extractJSON(from: response)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw LLMServiceError.invalidResponse
        }
        
        do {
            let plannerResponse = try JSONDecoder().decode(PlannerResponse.self, from: data)
            return plannerResponse.goals
        } catch {
            print("🧠 [Planner] JSON decode error: \(error)")
            // Try to parse as raw array
            if let goals = try? JSONDecoder().decode([MesoGoal].self, from: data) {
                return goals
            }
            throw LLMServiceError.invalidResponse
        }
    }
    
    private func parseNavigatorResponse(_ response: String) throws -> MicroInstruction {
        let cleanedResponse = extractJSON(from: response)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw LLMServiceError.invalidResponse
        }
        
        do {
            return try JSONDecoder().decode(MicroInstruction.self, from: data)
        } catch {
            print("🧭 [Navigator] JSON decode error: \(error)")
            // Fallback: create instruction from raw response
            return MicroInstruction(
                instruction: response,
                successCriteria: "User confirms step is complete",
                memoryToSave: [:]
            )
        }
    }
    
    private func parseWatcherResponse(_ response: String) throws -> WatcherResult {
        let cleanedResponse = extractJSON(from: response)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw LLMServiceError.invalidResponse
        }
        
        do {
            return try JSONDecoder().decode(WatcherResult.self, from: data)
        } catch {
            print("👁️ [Watcher] JSON decode error: \(error)")
            // Fallback: check for keywords
            let lowercased = response.lowercased()
            let isComplete = lowercased.contains("\"is_complete\": true") || 
                            lowercased.contains("\"is_complete\":true") ||
                            lowercased.contains("complete") && !lowercased.contains("not complete")
            return WatcherResult(isComplete: isComplete, reasoning: "Parsed from raw response")
        }
    }
    
    /// Extract JSON from a response that might have extra text
    private func extractJSON(from response: String) -> String {
        // Try to find JSON object
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        // Try to find JSON array
        if let startIndex = response.firstIndex(of: "["),
           let endIndex = response.lastIndex(of: "]") {
            return String(response[startIndex...endIndex])
        }
        return response
    }
}
