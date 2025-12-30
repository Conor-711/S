import Foundation
import AppKit
import Combine
import SwiftUI

/// ViewModel for the floating HUD panel
@MainActor
final class HUDViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentInstruction: String = "Ready to assist..."
    @Published var isProcessing: Bool = false
    @Published var steps: [TaskStep] = []
    @Published var currentStepIndex: Int = 0
    @Published var userGoal: String = ""
    @Published var isInputMode: Bool = false
    @Published var showSuccessCheckmark: Bool = false
    @Published var diagnosisResult: String? = nil
    
    // MARK: - Dependencies
    
    private let llmService: QwenLLMService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Callbacks
    
    var onActivateInputMode: (() -> Void)?
    var onDeactivateInputMode: (() -> Void)?
    var onContentSizeChanged: (() -> Void)?
    
    // MARK: - Initialization
    
    init(llmService: QwenLLMService = QwenLLMService()) {
        self.llmService = llmService
    }
    
    // MARK: - Public Methods
    
    /// Start a new task with the given goal
    func startTask(goal: String) {
        print("🤖 [HUDViewModel] Starting task with goal: \(goal)")
        userGoal = goal
        isProcessing = true
        currentInstruction = "Analyzing your request..."
        
        Task {
            print("🤖 [HUDViewModel] Calling LLM to generate plan...")
            let plan = await llmService.generatePlan(goal: goal, currentState: "Initial state")
            print("🤖 [HUDViewModel] Plan generated with \(plan.count) steps")
            
            await MainActor.run {
                self.steps = plan
                self.currentStepIndex = 0
                self.isProcessing = false
                
                if let firstStep = plan.first {
                    self.currentInstruction = firstStep.instruction
                } else {
                    self.currentInstruction = "Could not generate a plan. Please try again."
                }
            }
        }
    }
    
    /// Analyze the current screen and update instruction
    func analyzeScreen(_ image: NSImage) {
        print("🤖 [HUDViewModel] analyzeScreen called")
        guard !isProcessing else {
            print("🤖 [HUDViewModel] Skipping analysis - already processing")
            return
        }
        
        isProcessing = true
        print("🤖 [HUDViewModel] Starting screen analysis with LLM...")
        
        Task {
            let prompt = """
            Analyze this macOS screen. The user's goal is: \(userGoal)
            Current step: \(currentInstruction)
            
            Describe what you see and whether the current step appears to be completed.
            """
            
            if let analysis = await llmService.analyzeImage(image, prompt: prompt) {
                await MainActor.run {
                    self.processAnalysis(analysis)
                    self.isProcessing = false
                }
            } else {
                await MainActor.run {
                    self.isProcessing = false
                }
            }
        }
    }
    
    /// Mark current step as complete and move to next
    func completeCurrentStep() {
        guard currentStepIndex < steps.count else { return }
        
        steps[currentStepIndex] = steps[currentStepIndex].markCompleted()
        currentStepIndex += 1
        
        if currentStepIndex < steps.count {
            currentInstruction = steps[currentStepIndex].instruction
        } else {
            currentInstruction = "🎉 Task completed!"
        }
    }
    
    /// Request input mode activation
    func requestInputMode() {
        isInputMode = true
        onActivateInputMode?()
        onContentSizeChanged?()
    }
    
    /// Exit input mode
    func exitInputMode() {
        isInputMode = false
        onDeactivateInputMode?()
        onContentSizeChanged?()
    }
    
    /// Toggle input mode
    func toggleInputMode() {
        if isInputMode {
            exitInputMode()
        } else {
            requestInputMode()
        }
    }
    
    /// Reset the session
    func reset() {
        steps = []
        currentStepIndex = 0
        userGoal = ""
        currentInstruction = "Ready to assist..."
        isProcessing = false
        isInputMode = false
        showSuccessCheckmark = false
        diagnosisResult = nil
        onContentSizeChanged?()
    }
    
    // MARK: - Phase 3: Animation Handlers
    
    /// Handle successful step completion with animation
    func handleSuccess() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showSuccessCheckmark = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            withAnimation {
                self?.showSuccessCheckmark = false
            }
            self?.completeCurrentStep()
        }
    }
    
    /// Update instruction with animation
    func updateInstruction(_ newInstruction: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentInstruction = newInstruction
        }
    }
    
    // MARK: - Phase 3: Diagnosis (Track B)
    
    /// Set diagnosis result and expand the view
    func setDiagnosis(_ diagnosis: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            diagnosisResult = diagnosis
        }
        onContentSizeChanged?()
    }
    
    /// Dismiss the diagnosis view
    func dismissDiagnosis() {
        withAnimation(.easeInOut(duration: 0.25)) {
            diagnosisResult = nil
        }
        onContentSizeChanged?()
    }
    
    /// Mark diagnosis as fixed and dismiss
    func markDiagnosisFixed() {
        // Could log or track that the user fixed the issue
        print("🔧 [HUDViewModel] User marked diagnosis as fixed")
        dismissDiagnosis()
    }
    
    /// Run diagnosis check on current screen
    func runDiagnosis(with image: NSImage) {
        guard !isProcessing else { return }
        
        isProcessing = true
        
        Task {
            let prompt = """
            Analyze this macOS screen for any potential issues or blockers.
            The user's goal is: \(userGoal)
            Current step: \(currentInstruction)
            
            If you see any issue that might be blocking progress (e.g., error dialog, wrong screen, missing element), describe it briefly and suggest a fix.
            If everything looks fine, respond with "OK".
            """
            
            if let analysis = await llmService.analyzeImage(image, prompt: prompt) {
                await MainActor.run {
                    if !analysis.lowercased().contains("ok") && analysis.count > 10 {
                        self.setDiagnosis(analysis)
                    }
                    self.isProcessing = false
                }
            } else {
                await MainActor.run {
                    self.isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func processAnalysis(_ analysis: String) {
        let lowercased = analysis.lowercased()
        if lowercased.contains("completed") || lowercased.contains("done") || lowercased.contains("success") {
            handleSuccess()
        }
    }
}
