import SwiftUI
import AppKit

/// V9: Collection Box View for Visual Knowledge Base
/// Shows captured note count with badge and fly-in animation
/// Per v9.md Section 4: UI/UX - The Collection Box
struct CollectionBoxView: View {
    @ObservedObject var knowledgeBase: KnowledgeBaseService
    
    // Animation state
    @State private var showFlyingThumbnail: Bool = false
    @State private var thumbnailPosition: CGPoint = .zero
    @State private var thumbnailScale: CGFloat = 1.0
    @State private var thumbnailOpacity: Double = 1.0
    @State private var badgeBounce: Bool = false
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    
    // Callbacks
    var onTap: (() -> Void)?
    
    // Layout
    private let iconSize: CGFloat = 24
    
    var body: some View {
        ZStack {
            // Collection Box Button
            collectionBoxButton
            
            // Flying Thumbnail Animation
            if showFlyingThumbnail {
                flyingThumbnail
            }
            
            // Toast notification
            if showToast {
                toastView
            }
        }
    }
    
    // MARK: - Collection Box Button
    
    private var collectionBoxButton: some View {
        Button(action: {
            onTap?()
        }) {
            ZStack(alignment: .topTrailing) {
                // Icon
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(badgeBounce ? 1.15 : 1.0)
                
                // Badge (count)
                if knowledgeBase.noteCount > 0 {
                    badgeView
                        .offset(x: 8, y: -6)
                        .scaleEffect(badgeBounce ? 1.2 : 1.0)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("Click to generate report from \(knowledgeBase.noteCount) captured notes")
    }
    
    private var badgeView: some View {
        Text("\(knowledgeBase.noteCount)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(minWidth: 16, minHeight: 16)
            .background(
                Circle()
                    .fill(Color.red)
            )
    }
    
    // MARK: - Flying Thumbnail Animation
    
    private var flyingThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [.cyan.opacity(0.5), .blue.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 40)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.white)
            )
            .scaleEffect(thumbnailScale)
            .opacity(thumbnailOpacity)
            .position(thumbnailPosition)
    }
    
    // MARK: - Toast View
    
    private var toastView: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(toastMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Animation Methods
    
    /// Trigger fly-in animation when a new note is captured
    /// Per v9.md Section 4.2: Animation Spec ("The Fly-In")
    func triggerFlyInAnimation(from startPoint: CGPoint, to endPoint: CGPoint) {
        // Reset state
        thumbnailPosition = startPoint
        thumbnailScale = 1.0
        thumbnailOpacity = 1.0
        showFlyingThumbnail = true
        
        // Animate along bezier-like path
        withAnimation(.easeInOut(duration: 0.4)) {
            thumbnailPosition = endPoint
            thumbnailScale = 0.3
        }
        
        // Fade out at arrival
        withAnimation(.easeOut(duration: 0.1).delay(0.35)) {
            thumbnailOpacity = 0
        }
        
        // Bounce the badge
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.4)) {
            badgeBounce = true
        }
        
        // Reset states
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showFlyingThumbnail = false
            badgeBounce = false
        }
    }
    
    /// Show toast notification
    func showToastNotification(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
}

// MARK: - Collection Box Container (with coordination)

/// Container view that manages the Collection Box and its animations
struct CollectionBoxContainer: View {
    @ObservedObject var knowledgeBase: KnowledgeBaseService
    @State private var boxFrame: CGRect = .zero
    @State private var showingNotesList: Bool = false
    
    var onGenerateReport: (() async -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Collection Box
            CollectionBoxView(knowledgeBase: knowledgeBase) {
                if knowledgeBase.noteCount > 0 {
                    Task {
                        await onGenerateReport?()
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            boxFrame = geo.frame(in: .global)
                        }
                }
            )
            .onHover { hovering in
                if hovering && knowledgeBase.noteCount > 0 {
                    showingNotesList = true
                } else {
                    showingNotesList = false
                }
            }
            
            // Notes list popover on hover
            if showingNotesList {
                notesListView
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showingNotesList)
    }
    
    private var notesListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(knowledgeBase.notes.suffix(5)) { note in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 6, height: 6)
                    
                    Text(note.caption)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            
            if knowledgeBase.noteCount > 5 {
                Text("... +\(knowledgeBase.noteCount - 5) more")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.8))
        )
        .frame(maxWidth: 200)
    }
}

// MARK: - Preview

#Preview("Collection Box") {
    @Previewable @StateObject var service = KnowledgeBaseService(llmService: GeminiLLMService(), captureService: ScreenCaptureService())
    
    VStack(spacing: 20) {
        // Empty state
        CollectionBoxView(knowledgeBase: service)
        
        // With notes
        CollectionBoxContainer(knowledgeBase: service)
    }
    .padding(40)
    .background(Color.black)
    .onAppear {
        service.addNote(caption: "Python web scraping code", intent: "Code reference")
        service.addNote(caption: "Beautiful UI design mockup", intent: "Design inspiration")
        service.addNote(caption: "Terminal error log", intent: "Debug reference")
    }
}
