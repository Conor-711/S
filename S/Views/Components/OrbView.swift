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

// MARK: - Digital Stationery Design Constants
/// Design system based on "Digital Stationery" style
/// Font: Newsreader (Serif) for text, Inter (Sans) for UI labels
/// Color: #FFFFFF (Card Bg), #111111 (Text), #EAEAEA (Border)
/// Shadow: 0px 4px 12px rgba(0,0,0,0.08)
struct CardDesign {
    // Colors
    static let cardBackground = Color.white
    static let textPrimary = Color(hex: "111111")
    static let textSecondary = Color(hex: "111111").opacity(0.6)
    static let border = Color(hex: "EAEAEA")
    static let successGreen = Color(hex: "22C55E")
    
    // Shadow
    static let shadowColor = Color.black.opacity(0.08)
    static let shadowRadius: CGFloat = 12
    static let shadowY: CGFloat = 4
    
    // Corner radius
    static let collapsedCornerRadius: CGFloat = 8
    static let expandedCornerRadius: CGFloat = 12
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Card-style collapsed state - "Digital Stationery" bookmark/tag
/// Replaces the orb with a minimal white card anchor
struct OrbView: View {
    let feedbackState: FeedbackState
    let isActive: Bool       // Agent is navigating/watching
    let isRecording: Bool    // Voice recording state
    
    @State private var breathingOpacity: CGFloat = 0.6
    @State private var successScale: CGFloat = 1.0
    
    // Card size (compact anchor)
    private let cardWidth: CGFloat = 48
    private let cardHeight: CGFloat = 48
    
    var body: some View {
        ZStack {
            // Card background - pure white with fine border
            RoundedRectangle(cornerRadius: CardDesign.collapsedCornerRadius)
                .fill(CardDesign.cardBackground)
            
            // Fine border
            RoundedRectangle(cornerRadius: CardDesign.collapsedCornerRadius)
                .strokeBorder(CardDesign.border, lineWidth: 1)
            
            // Content based on feedback state
            if case .success = feedbackState {
                successFlashView
            } else {
                anchorIconView
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(successScale)
        .shadow(color: CardDesign.shadowColor, radius: CardDesign.shadowRadius, x: 0, y: CardDesign.shadowY)
        .onChange(of: feedbackState) { _, newState in
            handleFeedbackStateChange(newState)
        }
        .onAppear {
            startBreathingAnimation()
        }
    }
    
    // MARK: - Success Flash View
    
    private var successFlashView: some View {
        ZStack {
            // Green background fill
            RoundedRectangle(cornerRadius: CardDesign.collapsedCornerRadius - 2)
                .fill(CardDesign.successGreen)
                .padding(4)
            
            // Checkmark icon
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Anchor Icon View (replaces breathing wave)
    
    private var anchorIconView: some View {
        // Literary iconography - minimal text symbol "Aa" or simple icon
        Text("Aa")
            .font(.system(size: 16, weight: .medium, design: .serif))
            .foregroundColor(CardDesign.textPrimary)
            .opacity(breathingOpacity)
    }
    
    // MARK: - Animation Helpers
    
    private func startBreathingAnimation() {
        // Subtle opacity breathing for the anchor
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            breathingOpacity = isActive || isRecording ? 1.0 : 0.8
        }
    }
    
    private func handleFeedbackStateChange(_ state: FeedbackState) {
        switch state {
        case .success:
            // Subtle scale bump animation
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                successScale = 1.08
            }
            // Bounce back
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    successScale = 1.0
                }
            }
        case .idle, .capturing:
            successScale = 1.0
        }
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
