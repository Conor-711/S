import Foundation
import AppKit
import Combine

/// Orchestrates the AI agent loop: Planner -> Navigator -> Watcher -> Summarizer
@MainActor
final class AgentLogicController: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var sessionContext: AgentSessionContext?
    @Published private(set) var currentInstruction: String = "Ready to assist..."
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var agentState: AgentState = .idle
    @Published private(set) var error: String?
    @Published private(set) var currentValueToCopy: String?
    
    // MARK: - Dependencies
    
    private let llmService: QwenLLMService
    private var screenCaptureSubscription: AnyCancellable?
    private var watcherTask: Task<Void, Never>?
    private var actionHistory: [String] = []
    
    // MARK: - Agent State
    
    enum AgentState: Equatable {
        case idle
        case planning
        case navigating
        case watching
        case summarizing
        case completed
        case error(String)
    }
    
    // MARK: - Initialization
    
    init(llmService: QwenLLMService = QwenLLMService()) {
        self.llmService = llmService
    }
    
    // MARK: - Public Methods
    
    /// Start a new agent session with a goal
    func startSession(goal: String, initialImage: NSImage) {
        print("🎯 [AgentController] Starting session with goal: \(goal)")
        
        sessionContext = AgentSessionContext(userGoal: goal)
        actionHistory = []
        error = nil
        
        Task {
            await processNextStep(with: initialImage)
        }
    }
    
    /// Process the next step in the agent loop
    func processNextStep(with image: NSImage) async {
        guard var context = sessionContext else {
            print("🎯 [AgentController] No active session")
            return
        }
        
        guard !isProcessing else {
            print("🎯 [AgentController] Already processing, skipping")
            return
        }
        
        isProcessing = true
        
        do {
            // Step 1: If no meso goals, call Planner
            if context.currentMesoGoals.isEmpty || !context.hasMoreMesoGoals {
                print("🎯 [AgentController] No meso goals, calling Planner")
                agentState = .planning
                currentInstruction = "Analyzing your request and creating a plan..."
                
                let goals = try await llmService.sendPlannerRequest(
                    goal: context.userGoal,
                    history: context.formattedHistory,
                    image: image
                )
                
                if goals.isEmpty {
                    throw AgentError.noPlanGenerated
                }
                
                context.currentMesoGoals = goals
                context.currentMesoIndex = 0
                sessionContext = context
                
                print("🎯 [AgentController] Plan created with \(goals.count) milestones")
            }
            
            // Step 2: Get current meso goal
            guard let currentMeso = context.currentMesoGoal else {
                agentState = .completed
                currentInstruction = "🎉 All tasks completed!"
                isProcessing = false
                return
            }
            
            // Step 3: Call Navigator
            print("🎯 [AgentController] Calling Navigator for: \(currentMeso.title)")
            agentState = .navigating
            
            let instruction = try await llmService.sendNavigatorRequest(
                meso: currentMeso,
                image: image,
                blackboard: context.blackboard
            )
            
            // Update context with any memory to save
            if let memoryToSave = instruction.memoryToSave, !memoryToSave.isEmpty {
                context.updateBlackboard(memoryToSave)
                sessionContext = context
            }
            
            context.currentInstruction = instruction
            sessionContext = context
            
            // Update UI
            currentInstruction = instruction.instruction
            currentValueToCopy = instruction.valueToCopy
            actionHistory.append(instruction.instruction)
            
            // Step 4: Start Watcher
            agentState = .watching
            print("🎯 [AgentController] Instruction delivered, waiting for user action")
            
            isProcessing = false
            
        } catch {
            print("🎯 [AgentController] Error: \(error)")
            self.error = error.localizedDescription
            agentState = .error(error.localizedDescription)
            currentInstruction = "Error: \(error.localizedDescription). Please try again."
            isProcessing = false
        }
    }
    
    /// Check if current step criteria is met (called when screen changes)
    func checkStepCompletion(with image: NSImage) async {
        guard var context = sessionContext,
              let instruction = context.currentInstruction,
              agentState == .watching else {
            return
        }
        
        guard !isProcessing else { return }
        
        isProcessing = true
        
        do {
            let isComplete = try await llmService.sendWatcherRequest(
                criteria: instruction.successCriteria,
                image: image
            )
            
            if isComplete {
                print("🎯 [AgentController] Step completed! Moving to next...")
                
                // Check if this completes the current meso goal
                // For simplicity, we'll move to next meso after each instruction
                // In a more sophisticated version, we'd track multiple instructions per meso
                
                agentState = .summarizing
                
                // Summarize the completed action
                if let currentMeso = context.currentMesoGoal {
                    let summary = try await llmService.sendSummarizerRequest(
                        completedMeso: currentMeso,
                        actions: actionHistory
                    )
                    
                    context.addToHistory(summary)
                    context.advanceToNextMeso()
                    actionHistory = []
                    sessionContext = context
                }
                
                // Process next step
                isProcessing = false
                await processNextStep(with: image)
                
            } else {
                print("🎯 [AgentController] Step not yet complete")
                isProcessing = false
            }
            
        } catch {
            print("🎯 [AgentController] Watcher error: \(error)")
            isProcessing = false
        }
    }
    
    /// Subscribe to screen capture updates
    func subscribeToScreenUpdates(from publisher: Published<NSImage?>.Publisher) {
        screenCaptureSubscription = publisher
            .compactMap { $0 }
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.checkStepCompletion(with: image)
                }
            }
    }
    
    /// Mark current step as manually completed by user
    func markStepComplete() {
        guard var context = sessionContext else { return }
        
        Task {
            agentState = .summarizing
            
            if let currentMeso = context.currentMesoGoal {
                do {
                    let summary = try await llmService.sendSummarizerRequest(
                        completedMeso: currentMeso,
                        actions: actionHistory
                    )
                    
                    context.addToHistory(summary)
                    context.advanceToNextMeso()
                    actionHistory = []
                    sessionContext = context
                    
                    // Get next instruction if we have a current image
                    // The UI should call processNextStep with a fresh image
                    agentState = .idle
                    currentInstruction = "Step completed! Click 'Next' for the next instruction."
                    
                } catch {
                    print("🎯 [AgentController] Summarizer error: \(error)")
                }
            }
        }
    }
    
    /// Reset the agent session
    func reset() {
        watcherTask?.cancel()
        watcherTask = nil
        screenCaptureSubscription?.cancel()
        screenCaptureSubscription = nil
        
        sessionContext = nil
        currentInstruction = "Ready to assist..."
        isProcessing = false
        agentState = .idle
        error = nil
        actionHistory = []
        currentValueToCopy = nil
    }
    
    /// Get current progress
    var progress: (current: Int, total: Int) {
        guard let context = sessionContext else { return (0, 0) }
        return (context.completedMesoCount, context.currentMesoGoals.count)
    }
    
    /// Get current meso goal title
    var currentMilestone: String? {
        sessionContext?.currentMesoGoal?.title
    }
}

// MARK: - Agent Errors

enum AgentError: LocalizedError {
    case noPlanGenerated
    case noMesoGoal
    case sessionNotActive
    
    var errorDescription: String? {
        switch self {
        case .noPlanGenerated:
            return "Could not generate a plan. Please try rephrasing your goal."
        case .noMesoGoal:
            return "No current milestone to work on."
        case .sessionNotActive:
            return "No active session. Please start a new task."
        }
    }
}
