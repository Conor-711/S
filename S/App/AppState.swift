import Foundation
import AppKit
import Combine

/// Global state manager for the AI Navigator application
@MainActor
@Observable
final class AppState {
    
    // MARK: - Published Properties
    
    var currentImage: NSImage?
    var currentInstruction: String = "Ready to assist..."
    var isProcessing: Bool = false
    var sessionContext: SessionContext?
    var captureError: String?
    
    // MARK: - Services
    
    let captureService: ScreenCaptureService
    let llmService: QwenLLMService
    let hudViewModel: HUDViewModel
    let agentController: AgentLogicController
    let screenManager: ScreenManager
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        self.captureService = ScreenCaptureService()
        self.llmService = QwenLLMService()
        self.agentController = AgentLogicController()
        self.hudViewModel = HUDViewModel()
        self.screenManager = ScreenManager()
        
        setupBindings()
        setupScreenManager()
    }
    
    // MARK: - Public Methods
    
    /// Start a new session and boot up the capture service
    func startSession() {
        print("🚀 [AppState] Starting session...")
        sessionContext = SessionContext(userGoal: "")
        
        Task {
            let hasPermission = await captureService.requestPermission()
            
            if hasPermission {
                print("🚀 [AppState] Permission granted, starting capture polling")
                captureService.startPolling(interval: 2.0)
            } else {
                print("🚀 [AppState] Permission DENIED")
                captureError = "Screen capture permission denied. Please grant permission in System Preferences > Privacy & Security > Screen Recording."
            }
        }
    }
    
    /// Stop the current session
    func stopSession() {
        captureService.stopPolling()
        sessionContext = nil
        currentImage = nil
        currentInstruction = "Session ended"
    }
    
    /// Set a new user goal and begin task planning
    func setGoal(_ goal: String) {
        guard var context = sessionContext else {
            sessionContext = SessionContext(userGoal: goal)
            return
        }
        
        context.userGoal = goal
        sessionContext = context
        
        hudViewModel.startTask(goal: goal)
    }
    
    /// Process the current screen state
    func analyzeCurrentScreen() {
        guard let image = currentImage else { return }
        hudViewModel.analyzeScreen(image)
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
        
        // Agent controller bindings (Phase 2)
        agentController.$currentInstruction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instruction in
                self?.currentInstruction = instruction
            }
            .store(in: &cancellables)
        
        agentController.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processing in
                self?.isProcessing = processing
            }
            .store(in: &cancellables)
        
        // Subscribe agent to screen updates
        agentController.subscribeToScreenUpdates(from: captureService.$currentScreenshot)
        
        // Legacy HUDViewModel bindings (fallback)
        hudViewModel.$currentInstruction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instruction in
                // Only use if agent is idle
                guard let self = self, self.agentController.agentState == .idle else { return }
                self.currentInstruction = instruction
            }
            .store(in: &cancellables)
        
        hudViewModel.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processing in
                guard let self = self, self.agentController.agentState == .idle else { return }
                self.isProcessing = processing
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Phase 2: Agent Methods
    
    /// Start the AI agent with a goal
    func startAgent(goal: String) {
        guard let image = currentImage else {
            print("🚀 [AppState] Cannot start agent - no screenshot available")
            return
        }
        
        agentController.startSession(goal: goal, initialImage: image)
    }
    
    /// Request next step from the agent
    func requestNextStep() {
        guard let image = currentImage else { return }
        
        Task {
            await agentController.processNextStep(with: image)
        }
    }
    
    /// Mark current step as complete
    func markStepComplete() {
        agentController.markStepComplete()
    }
    
    /// Reset agent state
    func resetAgent() {
        agentController.reset()
    }
    
    // MARK: - Phase 4: Session Reset & Screen Management
    
    /// Reset the entire session (clears all data)
    func resetSession() {
        print("🔄 [AppState] Resetting session...")
        
        // Reset agent
        agentController.reset()
        
        // Reset HUD
        hudViewModel.reset()
        
        // Clear state
        currentImage = nil
        currentInstruction = "Ready to assist..."
        isProcessing = false
        sessionContext = nil
        
        print("🔄 [AppState] Session reset complete")
    }
    
    /// Setup screen manager for multi-monitor support
    private func setupScreenManager() {
        screenManager.startTracking()
        
        screenManager.onScreenChanged = { [weak self] screen, displayID in
            guard let self = self else { return }
            
            print("🖥️ [AppState] Screen changed, updating capture target")
            self.captureService.updateTargetScreen(displayID: displayID)
        }
    }
}
