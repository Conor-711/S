import SwiftUI
import AppKit

/// Main SwiftUI view for the floating HUD panel
struct HUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    @ObservedObject var agentController: AgentLogicController
    @State private var goalInput: String = ""
    @State private var isInputExpanded: Bool = false
    @State private var showSuccessCheckmark: Bool = false
    @State private var showCopiedToast: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Status + Instruction + Action Buttons
            topRow
            
            // Middle Row: Input Field (conditional)
            if isInputExpanded {
                CompactInputView(
                    text: $goalInput,
                    placeholder: "Enter your goal...",
                    onSubmit: submitGoal,
                    onCancel: cancelInput
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Milestone indicator
            milestoneView
            
            // Progress indicators
            progressView
            
            // Bottom Row: Diagnosis (conditional)
            if let diagnosis = viewModel.diagnosisResult {
                DiagnosisView(
                    text: diagnosis,
                    onDismiss: { viewModel.dismissDiagnosis() },
                    onFixed: { viewModel.markDiagnosisFixed() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: isInputExpanded)
        .animation(.easeInOut(duration: 0.25), value: viewModel.diagnosisResult != nil)
    }
    
    // MARK: - Top Row
    
    private var topRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status Indicator
            StatusIndicator(state: processingState)
                .padding(.top, 5)
            
            // Main Instruction Text
            VStack(alignment: .leading, spacing: 4) {
                if showSuccessCheckmark {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Step completed!")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    HStack(spacing: 6) {
                        Text(agentController.currentInstruction)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut(duration: 0.2), value: agentController.currentInstruction)
                        
                        // Copy Button (Phase 4)
                        if let valueToCopy = agentController.currentValueToCopy, !valueToCopy.isEmpty {
                            Button(action: { copyToClipboard(valueToCopy) }) {
                                Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(showCopiedToast ? .green : .blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Copy to clipboard")
                        }
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            actionButtonsCompact
        }
    }
    
    // MARK: - Compact Action Buttons
    
    private var actionButtonsCompact: some View {
        HStack(spacing: 6) {
            // Toggle Input Button
            Button(action: toggleInput) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundColor(isInputExpanded ? .blue : .white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .help("New Task")
            
            // Force Next / Done Button
            if agentController.agentState == .watching {
                Button(action: { handleStepComplete() }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Mark Done")
            } else if agentController.agentState == .idle && agentController.progress.total > 0 {
                Button(action: { onRequestNextStep?() }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Next Step")
            }
            
            // Reset Button
            Button(action: resetAll) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset")
            
            // Close Button (Phase 4)
            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Close")
        }
    }
    
    // MARK: - Milestone View
    
    private var milestoneView: some View {
        Group {
            if let milestone = agentController.currentMilestone {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                    Text(milestone)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    
                    // State label
                    stateLabel
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var stateLabel: some View {
        Group {
            switch agentController.agentState {
            case .idle:
                EmptyView()
            case .planning:
                Label("Planning", systemImage: "brain")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            case .navigating:
                Label("Thinking", systemImage: "gearshape.2")
                    .font(.system(size: 9))
                    .foregroundColor(.blue)
            case .watching:
                Label("Watching", systemImage: "eye")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            case .summarizing:
                Label("Saving", systemImage: "arrow.down.doc")
                    .font(.system(size: 9))
                    .foregroundColor(.purple)
            case .completed:
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            case .error:
                Label("Error", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        let progress = agentController.progress
        return Group {
            if progress.total > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<progress.total, id: \.self) { index in
                        Circle()
                            .fill(progressColor(for: index, current: progress.current))
                            .frame(width: 6, height: 6)
                    }
                    
                    Spacer()
                    
                    Text("\(progress.current)/\(progress.total)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundView: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.2)
        }
    }
    
    // MARK: - Computed Properties
    
    private var processingState: ProcessingState {
        switch agentController.agentState {
        case .idle:
            return .idle
        case .planning, .navigating, .summarizing:
            return .thinking
        case .watching:
            return .polling
        case .completed:
            return .success
        case .error:
            return .error
        }
    }
    
    // MARK: - Helper Methods
    
    private func progressColor(for index: Int, current: Int) -> Color {
        if index < current {
            return .green
        } else if index == current {
            return .blue
        } else {
            return .white.opacity(0.3)
        }
    }
    
    private func toggleInput() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isInputExpanded.toggle()
        }
        if isInputExpanded {
            viewModel.requestInputMode()
        } else {
            viewModel.exitInputMode()
        }
    }
    
    private func submitGoal() {
        guard !goalInput.isEmpty else { return }
        onStartAgent?(goalInput)
        goalInput = ""
        withAnimation {
            isInputExpanded = false
        }
        viewModel.exitInputMode()
    }
    
    private func cancelInput() {
        withAnimation {
            isInputExpanded = false
        }
        goalInput = ""
        viewModel.exitInputMode()
    }
    
    private func handleStepComplete() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showSuccessCheckmark = true
        }
        agentController.markStepComplete()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showSuccessCheckmark = false
            }
        }
    }
    
    private func resetAll() {
        agentController.reset()
        viewModel.reset()
        goalInput = ""
        isInputExpanded = false
        showSuccessCheckmark = false
    }
    
    // MARK: - Phase 4: Clipboard
    
    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedToast = false
            }
        }
        
        print("📋 [HUDView] Copied to clipboard: \(value)")
    }
    
    // Callbacks
    var onStartAgent: ((String) -> Void)?
    var onRequestNextStep: (() -> Void)?
    var onClose: (() -> Void)?
}

// MARK: - Custom Button Style

struct HUDButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isPrimary ? Color.blue : Color.white.opacity(0.15))
            .foregroundColor(.white)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    HUDView(viewModel: HUDViewModel(), agentController: AgentLogicController())
        .frame(width: 320, height: 220)
        .background(Color.black)
}
