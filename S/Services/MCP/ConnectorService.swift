import Foundation
import AppKit
import Combine

// MARK: - Connector Service
// Orchestrates the Snapshot-to-Action pipeline: Capture → VLM → MCP

@MainActor
@Observable
final class ConnectorService {
    
    // MARK: - Published State
    
    var currentAnalysis: VLMAnalysisResult?
    var executionState: ActionExecutionState
    var isAnalyzing: Bool = false
    var lastError: Error?
    
    // MARK: - Services
    
    private let captureService: ScreenCaptureService
    private let intentClassifier: IntentClassificationService
    private let actionRouter: ActionRouter
    private let notionClient: NotionMCPClient
    private let notionAPI: NotionAPIClient
    
    // MARK: - Configuration
    
    private let countdownDuration: Int = 3  // Seconds before auto-execution
    private var pendingContext: SnapshotContext?
    private var countdownTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(captureService: ScreenCaptureService, llmService: GeminiLLMService) {
        self.captureService = captureService
        self.notionClient = NotionMCPClient()
        self.notionAPI = NotionAPIClient.shared
        self.intentClassifier = IntentClassificationService(llmService: llmService)
        self.actionRouter = ActionRouter(notionClient: notionClient, imageUploader: MockImageUploader())
        self.executionState = ActionExecutionState()
    }
    
    // MARK: - Main Pipeline
    
    /// Capture screenshot and start the Snapshot-to-Action pipeline
    func captureAndAnalyze() async {
        print("📸 [Connector] Starting capture pipeline...")
        
        isAnalyzing = true
        lastError = nil
        currentAnalysis = nil
        
        defer { isAnalyzing = false }
        
        do {
            // 1. Capture screenshot
            await captureService.captureScreen()
            
            guard let image = captureService.currentScreenshot else {
                throw ConnectorError.noImageAvailable
            }
            
            // 2. Create context
            let context = SnapshotContext(
                image: image,
                browserURL: getBrowserURL(),
                timestamp: Date()
            )
            pendingContext = context
            
            // 3. Classify intent with VLM
            let result = try await intentClassifier.classifyIntent(context: context)
            currentAnalysis = result
            
            print("🎯 [Connector] Intent: \(result.primaryIntent.icon) \(result.primaryIntent.displayName)")
            print("   Title: \(result.title ?? "None")")
            print("   Confidence: \(String(format: "%.1f%%", result.confidenceScore * 100))")
            
            // 4. Start countdown (user can cancel or switch intent)
            startCountdown(intent: result.primaryIntent)
            
        } catch {
            print("❌ [Connector] Pipeline failed: \(error)")
            lastError = error
        }
    }
    
    /// Analyze an existing image (without capture)
    func analyzeImage(_ image: NSImage, browserURL: URL? = nil) async {
        print("🔍 [Connector] Analyzing provided image...")
        
        isAnalyzing = true
        lastError = nil
        currentAnalysis = nil
        
        defer { isAnalyzing = false }
        
        do {
            let context = SnapshotContext(
                image: image,
                browserURL: browserURL,
                timestamp: Date()
            )
            pendingContext = context
            
            let result = try await intentClassifier.classifyIntent(context: context)
            currentAnalysis = result
            
            print("🎯 [Connector] Intent: \(result.primaryIntent.icon) \(result.primaryIntent.displayName)")
            
            startCountdown(intent: result.primaryIntent)
            
        } catch {
            print("❌ [Connector] Analysis failed: \(error)")
            lastError = error
        }
    }
    
    // MARK: - Countdown & Execution
    
    /// Start countdown before auto-execution
    private func startCountdown(intent: IntentCategory) {
        executionState.startCountdown(duration: countdownDuration, intent: intent)
        
        countdownTask?.cancel()
        countdownTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(countdownDuration) * 1_000_000_000)
            
            if !Task.isCancelled {
                await executeCurrentAction()
            }
        }
    }
    
    /// Cancel countdown and clear pending action
    func cancelAction() {
        print("🚫 [Connector] Action cancelled")
        countdownTask?.cancel()
        executionState.cancel()
        pendingContext = nil
        currentAnalysis = nil
    }
    
    /// Execute immediately (skip countdown)
    func executeNow() async {
        countdownTask?.cancel()
        await executeCurrentAction()
    }
    
    /// Switch to secondary intent and execute
    func switchToSecondaryIntent() async {
        guard let analysis = currentAnalysis,
              let secondary = analysis.secondaryIntent else {
            print("⚠️ [Connector] No secondary intent available")
            return
        }
        
        print("🔄 [Connector] Switching to secondary intent: \(secondary.displayName)")
        
        // Create new analysis with swapped intents
        let swapped = VLMAnalysisResult(
            primaryIntent: secondary,
            secondaryIntent: analysis.primaryIntent,
            confidenceScore: analysis.confidenceScore,
            title: analysis.title,
            description: analysis.description,
            detectedTime: analysis.detectedTime,
            requiresImageUpload: analysis.requiresImageUpload,
            suggestedActionPayload: analysis.suggestedActionPayload
        )
        
        currentAnalysis = swapped
        await executeNow()
    }
    
    /// Execute the current pending action
    private func executeCurrentAction() async {
        guard let analysis = currentAnalysis,
              let context = pendingContext else {
            print("⚠️ [Connector] No pending action to execute")
            return
        }
        
        print("⚡ [Connector] Executing action...")
        executionState.markExecuting()
        
        do {
            let result = try await actionRouter.execute(result: analysis, context: context)
            executionState.markCompleted(result: result)
            
            print("✅ [Connector] Action completed: \(result.success ? "Success" : "Failed")")
            if let content = result.content {
                print("   Response: \(content.prefix(200))...")
            }
            
        } catch {
            print("❌ [Connector] Execution failed: \(error)")
            executionState.markFailed(error: error)
            lastError = error
        }
        
        // Clear pending state
        pendingContext = nil
    }
    
    // MARK: - Utility Methods
    
    /// Get current browser URL (if available via accessibility)
    private func getBrowserURL() -> URL? {
        // TODO: Implement accessibility-based URL extraction
        // For now, return nil
        return nil
    }
    
    /// Test Notion API connection
    func testNotionConnection() async -> Bool {
        let connected = await notionAPI.connect()
        if connected {
            print("✅ [Connector] Notion API connected")
            MCPSettings.shared.isNotionConnected = true
        } else {
            print("❌ [Connector] Notion API connection failed")
            MCPSettings.shared.isNotionConnected = false
        }
        return connected
    }
    
    /// Create a quick note in Notion (bypass VLM)
    func quickNoteToNotion(title: String, content: String) async throws -> String {
        let settings = MCPSettings.shared
        
        if let pageId = settings.notionTargetPageId {
            return try await notionAPI.createPage(parentId: pageId, parentType: .page, title: title, content: content)
        } else {
            throw NotionAPIError.noTargetConfigured
        }
    }
    
    /// Search Notion
    func searchNotion(query: String) async throws -> NotionSearchResult {
        return try await notionAPI.search(query: query)
    }
    
    /// Save VLM analysis result to Notion
    func saveAnalysisToNotion() async throws -> String {
        guard let analysis = currentAnalysis else {
            throw ConnectorError.noImageAvailable
        }
        
        let title = analysis.title ?? "Screenshot Analysis - \(Date().formatted())" 
        let content = """
        Category: \(analysis.primaryIntent.displayName)
        Confidence: \(String(format: "%.1f%%", analysis.confidenceScore * 100))
        
        \(analysis.description ?? "")
        """
        
        return try await notionAPI.saveVLMAnalysisResult(
            title: title,
            content: content,
            category: analysis.primaryIntent.displayName,
            confidence: analysis.confidenceScore
        )
    }
}

// MARK: - Connector State Summary

extension ConnectorService {
    
    /// Get a summary of current state for UI display
    var stateSummary: String {
        if isAnalyzing {
            return "Analyzing screenshot..."
        }
        
        if executionState.isExecuting {
            return "Executing action..."
        }
        
        if executionState.countdown > 0, let intent = executionState.currentIntent {
            return "\(intent.icon) \(intent.displayName) in \(executionState.countdown)s"
        }
        
        if let result = executionState.result {
            return result.success ? "✅ Done" : "❌ Failed"
        }
        
        if let error = lastError {
            return "❌ \(error.localizedDescription)"
        }
        
        return "Ready"
    }
}
