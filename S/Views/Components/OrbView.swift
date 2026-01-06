import SwiftUI

/// V10: Feedback state for capture animations
enum FeedbackState: Equatable {
    case idle
    case capturing      // During fly-in animation
    case success        // Green flash after capture
    
    var isAnimating: Bool {
        self != .idle
    }
}

/// V10: The Living Orb - Collapsed idle state with breathing waveform
/// Per v10.md Section 1.1: A perfect circle with organic Siri-like waveform
struct OrbView: View {
    let feedbackState: FeedbackState
    let isActive: Bool       // Agent is navigating/watching
    let isRecording: Bool    // Voice recording state
    
    @State private var breathingPhase: CGFloat = 0
    @State private var successScale: CGFloat = 1.0
    
    // Orb size (60x60 pt as per spec)
    private let orbSize: CGFloat = 60
    
    var body: some View {
        ZStack {
            // Background circle with glass effect
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.black.opacity(0.3), Color.black.opacity(0.6)],
                                center: .center,
                                startRadius: 5,
                                endRadius: 35
                            )
                        )
                )
            
            // Content based on feedback state
            if case .success = feedbackState {
                // Success State: Green flash
                successFlashView
            } else {
                // Idle/Capturing: Breathing waveform
                breathingWaveView
            }
            
            // Rim light
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .frame(width: orbSize, height: orbSize)
        .scaleEffect(successScale)
        .shadow(color: shadowColor.opacity(0.5), radius: 15, x: 0, y: 5)
        .onChange(of: feedbackState) { _, newState in
            handleFeedbackStateChange(newState)
        }
    }
    
    // MARK: - Success Flash View
    
    private var successFlashView: some View {
        ZStack {
            // Green fill
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.9), Color.green.opacity(0.6)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 30
                    )
                )
                .padding(8)
            
            // Checkmark icon
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: .green.opacity(0.6), radius: 12)
    }
    
    // MARK: - Breathing Wave View
    
    private var breathingWaveView: some View {
        ZStack {
            // Organic waveform
            OrbWaveformShape(phase: breathingPhase, isActive: isActive || isRecording)
                .stroke(
                    LinearGradient(
                        colors: waveColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 36, height: 20)
                .opacity(0.5 + 0.3 * Darwin.sin(breathingPhase))  // Breathing opacity
                .shadow(color: glowColor.opacity(0.6), radius: 8)
                .shadow(color: glowColor.opacity(0.3), radius: 4)
        }
        .onAppear {
            startBreathingAnimation()
        }
        .onChange(of: isActive) { _, _ in
            startBreathingAnimation()
        }
        .onChange(of: isRecording) { _, _ in
            startBreathingAnimation()
        }
    }
    
    // MARK: - Animation Helpers
    
    private func startBreathingAnimation() {
        // Reset phase for smooth restart
        breathingPhase = 0
        
        let duration: Double
        if isRecording {
            duration = 0.5   // Fast pulsing when recording
        } else if isActive {
            duration = 1.5   // Medium speed when active
        } else {
            duration = 4.0   // Slow breathing when idle (4s loop per spec)
        }
        
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            breathingPhase = .pi * 2
        }
    }
    
    private func handleFeedbackStateChange(_ state: FeedbackState) {
        switch state {
        case .success:
            // Scale bump animation (1.1x bounce per spec)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                successScale = 1.15
            }
            // Bounce back
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    successScale = 1.0
                }
            }
        case .idle, .capturing:
            successScale = 1.0
        }
    }
    
    // MARK: - Color Helpers
    
    private var waveColors: [Color] {
        isRecording ? [.red, .orange] : [.cyan, .blue]
    }
    
    private var glowColor: Color {
        isRecording ? .red : .cyan
    }
    
    private var shadowColor: Color {
        switch feedbackState {
        case .success: return .green
        case .capturing: return .orange
        case .idle: return .black
        }
    }
}

// MARK: - Orb Waveform Shape (Organic Siri-like wave)

struct OrbWaveformShape: Shape {
    var phase: CGFloat
    var isActive: Bool
    
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        
        // Amplitude varies based on state
        let baseAmplitude: CGFloat = isActive ? 6 : 4
        let amplitude = baseAmplitude * (0.8 + 0.4 * abs(sin(phase * 0.5)))  // Breathing modulation
        
        let frequency: CGFloat = 2.0
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        // Create smooth organic wave
        for x in stride(from: 0, through: rect.width, by: 0.5) {
            let relativeX = x / rect.width
            
            // Multi-frequency wave for organic feel
            let wave1 = sin((relativeX * frequency * .pi) + phase)
            let wave2 = sin((relativeX * frequency * 1.5 * .pi) + phase * 0.7) * 0.3
            
            let y = midY + (wave1 + wave2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// MARK: - Preview

#Preview("Orb View - Idle") {
    VStack(spacing: 30) {
        OrbView(feedbackState: .idle, isActive: false, isRecording: false)
        OrbView(feedbackState: .idle, isActive: true, isRecording: false)
        OrbView(feedbackState: .idle, isActive: false, isRecording: true)
        OrbView(feedbackState: .success, isActive: false, isRecording: false)
    }
    .padding(40)
    .background(Color.black)
}
