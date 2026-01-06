import Foundation
import AppKit

// MARK: - Action Router
// Routes VLM intent classification to appropriate MCP tool execution

@MainActor
final class ActionRouter: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let notionClient: NotionMCPClient
    private let imageUploader: ImageUploaderProtocol?
    
    // Future MCP clients
    // private let calendarClient: CalendarMCPClient?
    // private let linearClient: LinearMCPClient?
    
    // MARK: - Initialization
    
    init(notionClient: NotionMCPClient, imageUploader: ImageUploaderProtocol? = nil) {
        self.notionClient = notionClient
        self.imageUploader = imageUploader
    }
    
    // MARK: - Main Execution
    
    /// Execute action based on VLM analysis result
    func execute(result: VLMAnalysisResult, context: SnapshotContext) async throws -> MCPToolResult {
        print("🚀 [ActionRouter] Executing intent: \(result.primaryIntent.icon) \(result.primaryIntent.displayName)")
        print("   Confidence: \(String(format: "%.1f%%", result.confidenceScore * 100))")
        
        var finalArgs = result.suggestedActionPayload
        
        // 1. Handle Image Upload if required
        if result.requiresImageUpload, let uploader = imageUploader {
            print("📤 [ActionRouter] Uploading image...")
            let hostedURL = try await uploader.upload(context.image)
            finalArgs["image_url"] = hostedURL.absoluteString
        }
        
        // 2. Inject Browser URL if exists (Context Recovery)
        if let url = context.browserURL {
            finalArgs["source_url"] = url.absoluteString
        }
        
        // 3. Add timestamp
        finalArgs["captured_at"] = ISO8601DateFormatter().string(from: context.timestamp)
        
        // 4. Dispatch to specific MCP based on intent
        switch result.primaryIntent {
        case .calendar:
            return try await executeCalendarAction(result: result, args: finalArgs)
            
        case .notion:
            return try await executeNotionAction(result: result, args: finalArgs)
            
        case .linear:
            return try await executeLinearAction(result: result, args: finalArgs)
            
        case .design:
            return try await executeDesignAction(result: result, args: finalArgs)
            
        case .unknown:
            throw RouterError.intentUnclear
        }
    }
    
    // MARK: - Intent-Specific Execution
    
    /// Calendar: Create event (Future - placeholder)
    private func executeCalendarAction(result: VLMAnalysisResult, args: [String: String]) async throws -> MCPToolResult {
        print("📅 [ActionRouter] Calendar action requested")
        
        // TODO: Implement CalendarMCPClient
        // For now, save to Notion as a fallback
        let title = result.title ?? "Scheduled Event"
        var content = result.description ?? ""
        
        if let time = result.detectedTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            content = "**Time:** \(formatter.string(from: time))\n\n\(content)"
        }
        
        if let sourceURL = args["source_url"] {
            content += "\n\n**Source:** \(sourceURL)"
        }
        
        return try await notionClient.createPage(title: "📅 \(title)", content: content)
    }
    
    /// Notion: Create page
    private func executeNotionAction(result: VLMAnalysisResult, args: [String: String]) async throws -> MCPToolResult {
        print("📝 [ActionRouter] Notion action")
        
        let title = result.title ?? "Captured Note"
        var content = result.description ?? "Captured from screenshot"
        
        // Add source URL if available
        if let sourceURL = args["source_url"] {
            content += "\n\n---\n**Source:** \(sourceURL)"
        }
        
        // Add capture timestamp
        if let capturedAt = args["captured_at"] {
            content += "\n**Captured:** \(capturedAt)"
        }
        
        return try await notionClient.createPage(title: title, content: content)
    }
    
    /// Linear: Create issue (Future - placeholder)
    private func executeLinearAction(result: VLMAnalysisResult, args: [String: String]) async throws -> MCPToolResult {
        print("🐛 [ActionRouter] Linear action requested")
        
        // TODO: Implement LinearMCPClient
        // For now, save to Notion with bug tag
        let title = result.title ?? "Bug Report"
        var content = "## Bug Report\n\n"
        content += result.description ?? "Error captured from screenshot"
        
        if let imageURL = args["image_url"] {
            content += "\n\n### Screenshot\n![\(title)](\(imageURL))"
        }
        
        if let sourceURL = args["source_url"] {
            content += "\n\n### Source\n\(sourceURL)"
        }
        
        return try await notionClient.createPage(title: "🐛 \(title)", content: content)
    }
    
    /// Design: Save inspiration (Future - Figma/Gallery)
    private func executeDesignAction(result: VLMAnalysisResult, args: [String: String]) async throws -> MCPToolResult {
        print("🎨 [ActionRouter] Design action requested")
        
        // TODO: Implement FigmaMCPClient
        // For now, save to Notion design gallery
        let title = result.title ?? "Design Inspiration"
        var content = "## Design Reference\n\n"
        content += result.description ?? "Visual inspiration captured"
        
        if let imageURL = args["image_url"] {
            content += "\n\n### Preview\n![\(title)](\(imageURL))"
        }
        
        if let sourceURL = args["source_url"] {
            content += "\n\n### Source\n\(sourceURL)"
        }
        
        return try await notionClient.createPage(title: "🎨 \(title)", content: content)
    }
    
    // MARK: - Utility Methods
    
    /// Check if a specific MCP is configured for an intent
    func isMCPConfigured(for intent: IntentCategory) -> Bool {
        switch intent {
        case .calendar:
            return false // TODO: CalendarMCPClient
        case .notion:
            return true
        case .linear:
            return false // TODO: LinearMCPClient
        case .design:
            return true // Falls back to Notion
        case .unknown:
            return false
        }
    }
    
    /// Get available tools for debugging
    func getAvailableNotionTools() async throws -> [MCPTool] {
        return try await notionClient.listTools()
    }
}

// MARK: - Image Uploader Protocol

/// Protocol for image hosting service
protocol ImageUploaderProtocol: Sendable {
    func upload(_ image: NSImage) async throws -> URL
}

// MARK: - Mock Image Uploader (for testing)

final class MockImageUploader: ImageUploaderProtocol {
    func upload(_ image: NSImage) async throws -> URL {
        // In production, implement real image hosting (e.g., Cloudinary, S3)
        print("📷 [MockImageUploader] Simulating image upload...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
        return URL(string: "https://placeholder.com/uploaded-image-\(UUID().uuidString).png")!
    }
}

// MARK: - Execution State

/// State for tracking action execution (useful for UI countdown)
@MainActor
@Observable
final class ActionExecutionState {
    var isExecuting: Bool = false
    var countdown: Int = 0
    var currentIntent: IntentCategory?
    var result: MCPToolResult?
    var error: Error?
    
    private var countdownTask: Task<Void, Never>?
    
    /// Start countdown before execution
    func startCountdown(duration: Int, intent: IntentCategory) {
        countdown = duration
        currentIntent = intent
        isExecuting = false
        result = nil
        error = nil
        
        countdownTask?.cancel()
        countdownTask = Task {
            for i in (0...duration).reversed() {
                if Task.isCancelled { break }
                countdown = i
                if i > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }
    
    /// Cancel countdown
    func cancel() {
        countdownTask?.cancel()
        countdown = 0
        currentIntent = nil
        isExecuting = false
    }
    
    /// Mark execution started
    func markExecuting() {
        isExecuting = true
        countdown = 0
    }
    
    /// Mark execution completed
    func markCompleted(result: MCPToolResult) {
        isExecuting = false
        self.result = result
    }
    
    /// Mark execution failed
    func markFailed(error: Error) {
        isExecuting = false
        self.error = error
    }
}
