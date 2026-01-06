import Foundation
import AppKit
import Combine

/// Simplified Global state manager for the AI Navigator application
/// V13: Removed URL processing, step buffer, and TR-P-D flow
/// Kept: Screen capture, VLM AI system, gesture triggers
@MainActor
@Observable
final class AppState {
    
    // MARK: - Published Properties
    
    var currentImage: NSImage?
    var currentInstruction: String = "Ready to assist..."
    var isProcessing: Bool = false
    var captureError: String?
    
    // MARK: - Services
    
    let captureService: ScreenCaptureService
    let llmService: GeminiLLMService
    let keyMonitor: GlobalKeyMonitor
    let knowledgeBaseService: KnowledgeBaseService
    let inputMonitor: InputMonitor
    let connectorService: ConnectorService
    
    // V1.1: Pipeline controller for Visual ETL
    let pipelineController: PipelineController
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        self.captureService = ScreenCaptureService()
        self.llmService = GeminiLLMService()
        self.keyMonitor = GlobalKeyMonitor()
        self.knowledgeBaseService = KnowledgeBaseService(llmService: llmService, captureService: captureService)
        self.inputMonitor = InputMonitor()
        self.connectorService = ConnectorService(captureService: captureService, llmService: llmService)
        self.pipelineController = PipelineController(llmService: llmService, captureService: captureService)
        
        setupBindings()
        setupInputMonitor()
    }
    
    // MARK: - Public Methods
    
    /// Start a new session (request permission)
    func startSession() {
        print("🚀 [AppState] Starting session...")
        
        Task {
            let hasPermission = await captureService.requestPermission()
            
            if hasPermission {
                print("🚀 [AppState] Permission granted, capture ready")
            } else {
                print("🚀 [AppState] Permission DENIED")
                captureError = "Screen capture permission denied. Please grant permission in System Preferences > Privacy & Security > Screen Recording."
            }
        }
    }
    
    /// Stop the current session
    func stopSession() {
        captureService.stopPolling()
        currentImage = nil
        currentInstruction = "Session ended"
    }
    
    /// Reset the session
    func resetSession() {
        print("🔄 [AppState] Resetting session")
        captureService.stopPolling()
        currentImage = nil
        currentInstruction = "Ready to assist..."
        isProcessing = false
        captureError = nil
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Screen capture bindings
        captureService.$currentScreenshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                if image != nil {
                    print("🔗 [AppState] Received new screenshot from capture service")
                }
                self?.currentImage = image
            }
            .store(in: &cancellables)
        
        captureService.$captureError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.captureError = error
            }
            .store(in: &cancellables)
    }
    
    
    // MARK: - Input Monitor Setup (Double-Cmd + Three-Finger Double-Tap)
    
    private func setupInputMonitor() {
        let handleTrigger: () -> Void = { [weak self] in
            guard let self = self else { return }
            print("⌨️ [AppState] Gesture trigger -> Capture Visual Note")
            Task {
                await self.knowledgeBaseService.captureVisualNote()
            }
        }
        
        inputMonitor.onDoubleCmdTrigger = handleTrigger
        inputMonitor.onThreeFingerDoubleTap = handleTrigger
        
        inputMonitor.startMonitoring()
        print("⌨️ [AppState] Input Monitor initialized (Double-Cmd + Three-Finger Double-Tap)")
    }
    
    // MARK: - Visual Knowledge Base Methods
    
    /// Capture a visual note
    func captureVisualNote() {
        Task {
            await knowledgeBaseService.captureVisualNote()
        }
    }
    
    /// Generate knowledge report and copy to clipboard
    func generateKnowledgeReport() {
        Task {
            do {
                try await knowledgeBaseService.generateReportAndCopy()
                print("📋 [AppState] Knowledge report copied to clipboard!")
            } catch {
                print("❌ [AppState] Failed to generate report: \(error)")
            }
        }
    }
    
    /// Clear all collected visual notes
    func clearVisualNotes() {
        knowledgeBaseService.clearAll()
    }
    
    // MARK: - VLM Analysis
    
    /// Analyze current screen with VLM
    func analyzeCurrentScreen(prompt: String? = nil) async -> String? {
        guard let image = currentImage else {
            print("❌ [AppState] No screenshot available for analysis")
            return nil
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let analysisPrompt = prompt ?? "Describe what you see on this screen in detail."
        return await llmService.analyzeImage(image, prompt: analysisPrompt)
    }
    
    // MARK: - Intelligent Connector Methods
    
    /// Capture and route to MCP based on VLM intent classification
    func captureAndRoute() {
        Task {
            await connectorService.captureAndAnalyze()
        }
    }
    
    /// Execute current pending MCP action immediately
    func executeConnectorAction() {
        Task {
            await connectorService.executeNow()
        }
    }
    
    /// Cancel pending MCP action
    func cancelConnectorAction() {
        connectorService.cancelAction()
    }
    
    /// Switch to secondary intent
    func switchToSecondaryIntent() {
        Task {
            await connectorService.switchToSecondaryIntent()
        }
    }
    
    /// Test Notion MCP connection
    func testNotionConnection() {
        Task {
            let success = await connectorService.testNotionConnection()
            if success {
                print("✅ [AppState] Notion MCP connected successfully")
            } else {
                print("❌ [AppState] Notion MCP connection failed")
            }
        }
    }
    
    /// Quick note to Notion (bypass VLM classification)
    func quickNoteToNotion(title: String, content: String) {
        Task {
            do {
                let pageId = try await connectorService.quickNoteToNotion(title: title, content: content)
                print("✅ [AppState] Quick note created: \(pageId)")
            } catch {
                print("❌ [AppState] Quick note failed: \(error)")
            }
        }
    }
    
    // MARK: - V1.1 Visual ETL Methods
    
    /// Initialize ETL schema (create S page and databases in Notion)
    /// Creates at workspace level automatically
    func initializeETLSchema() {
        Task {
            do {
                try await pipelineController.initializeSchema()
                print("✅ [AppState] ETL schema initialized")
            } catch {
                print("❌ [AppState] ETL schema initialization failed: \(error)")
            }
        }
    }
    
    /// Check if ETL is ready
    var isETLReady: Bool {
        NotionSchemaState.shared.isComplete && NotionOAuth2Service.shared.isAuthenticated
    }
    
    /// Reset ETL configuration
    func resetETLConfiguration() {
        NotionSchemaState.shared.clear()
        print("🔄 [AppState] ETL configuration reset")
    }
}
