import SwiftUI

/// Processing state for the status indicator
enum ProcessingState: Equatable {
    case idle
    case polling
    case thinking
    case success
    case error
}

/// A circular status indicator with animated states
struct StatusIndicator: View {
    let state: ProcessingState
    
    @State private var isAnimating = false
    @State private var rotation: Double = 0
    
    var body: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                startAnimation()
            }
            .onChange(of: state) { _, _ in
                startAnimation()
            }
    }
    
    private var stateColor: Color {
        switch state {
        case .idle:
            return .gray
        case .polling:
            return .blue
        case .thinking:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private var opacity: Double {
        switch state {
        case .polling:
            return isAnimating ? 0.5 : 1.0
        case .thinking:
            return isAnimating ? 0.3 : 1.0
        default:
            return 1.0
        }
    }
    
    private func startAnimation() {
        isAnimating = false
        rotation = 0
        
        switch state {
        case .polling:
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        case .thinking:
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        case .success, .error:
            withAnimation(.easeOut(duration: 0.2)) {
                isAnimating = false
            }
        case .idle:
            isAnimating = false
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            VStack {
                StatusIndicator(state: .idle)
                Text("Idle").font(.caption)
            }
            VStack {
                StatusIndicator(state: .polling)
                Text("Polling").font(.caption)
            }
            VStack {
                StatusIndicator(state: .thinking)
                Text("Thinking").font(.caption)
            }
            VStack {
                StatusIndicator(state: .success)
                Text("Success").font(.caption)
            }
            VStack {
                StatusIndicator(state: .error)
                Text("Error").font(.caption)
            }
        }
    }
    .padding()
    .background(Color.black)
}
