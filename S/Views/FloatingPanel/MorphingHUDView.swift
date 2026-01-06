import SwiftUI
import AppKit

/// V13: Simplified Morphing HUD View - Living Orb with capture animation
/// Removed: Step navigation, URL processing, TR-P-D states
/// Kept: Orb UI, capture fly-in animation, recording indicator
/// V1.2: Added user note input mode on hover during capture
struct MorphingHUDView: View {
    @ObservedObject var knowledgeBaseService: KnowledgeBaseService
    @ObservedObject var captureWindowState: CaptureWindowState = .shared
    var connectorService: ConnectorService?
    
    // Size State
    @State private var sizeState: SizeState = .collapsed
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var feedbackState: FeedbackState = .idle
    
    enum SizeState {
        case collapsed  // Living Orb (静默状态)
        case compact    // Compact bar (显示信息)
        case input      // Input mode (备注输入)
    }
    
    // Capture animation state
    @State private var showCaptureFlyIn: Bool = false
    @State private var capturedThumbnail: NSImage?
    @State private var flyInProgress: CGFloat = 0
    
    // V1.2: Input mode state
    @State private var userNoteText: String = ""
    @FocusState private var isInputFocused: Bool
    
    // Callbacks
    var onClose: (() -> Void)?
    var onGenerateReport: (() async -> Void)?
    var onNoteSubmitted: ((String?) -> Void)?  // V1.2: Called when note is submitted or cancelled
    
    init(
        knowledgeBaseService: KnowledgeBaseService,
        captureWindowState: CaptureWindowState = .shared,
        connectorService: ConnectorService? = nil,
        onClose: (() -> Void)? = nil,
        onGenerateReport: (() async -> Void)? = nil,
        onNoteSubmitted: ((String?) -> Void)? = nil
    ) {
        self.knowledgeBaseService = knowledgeBaseService
        self._captureWindowState = ObservedObject(wrappedValue: captureWindowState)
        self.connectorService = connectorService
        self.onClose = onClose
        self.onGenerateReport = onGenerateReport
        self.onNoteSubmitted = onNoteSubmitted
    }
    
    // Layout constants
    private let orbSize: CGFloat = 60
    private let compactWidth: CGFloat = 300
    private let compactHeight: CGFloat = 50
    private let inputWidth: CGFloat = 320
    private let inputBaseHeight: CGFloat = 56
    private let maxNoteLength: Int = 1000
    
    // MARK: - Computed Properties
    
    private var currentWidth: CGFloat {
        switch sizeState {
        case .collapsed: return orbSize
        case .compact: return compactWidth
        case .input: return inputWidth
        }
    }
    
    private var currentHeight: CGFloat {
        switch sizeState {
        case .collapsed: return orbSize
        case .compact: return compactHeight
        case .input: return calculatedInputHeight
        }
    }
    
    private var calculatedInputHeight: CGFloat {
        // Dynamic height based on text content
        let lineCount = max(1, userNoteText.components(separatedBy: "\n").count)
        let estimatedLines = max(lineCount, Int(ceil(Double(userNoteText.count) / 40.0)))
        let clampedLines = min(max(1, estimatedLines), 5)
        return inputBaseHeight + CGFloat(clampedLines - 1) * 20
    }
    
    private var cornerRadius: CGFloat {
        switch sizeState {
        case .collapsed: return orbSize / 2
        case .compact: return compactHeight / 2
        case .input: return 16
        }
    }
    
    var body: some View {
        ZStack {
            switch sizeState {
            case .collapsed:
                OrbView(
                    feedbackState: feedbackState,
                    isActive: false,
                    isRecording: false
                )
                .transition(.scale.combined(with: .opacity))
                
            case .compact:
                morphingBackground
                compactContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                
            case .input:
                morphingBackground
                inputContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            
            
            // Fly-in thumbnail overlay (during capture)
            if showCaptureFlyIn, let thumbnail = capturedThumbnail {
                captureFlyInOverlay(thumbnail: thumbnail)
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .contentShape(morphingShape)
        .clipShape(morphingShape)
        .overlay(sizeState != .collapsed ? rimLight : nil)
        .background(
            morphingShape
                .fill(Color.clear)
                .shadow(color: shadowColor.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .background(Color.clear)
        .onHover(perform: handleHover)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: sizeState)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: feedbackState)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: calculatedInputHeight)
        .onReceive(knowledgeBaseService.$lastCaptureEvent) { event in
            if let event = event {
                triggerCaptureAnimation(thumbnail: event.thumbnail)
            }
        }
    }
    
    // MARK: - Morphing Background
    
    private var morphingBackground: some View {
        ZStack {
            morphingShape
                .fill(.ultraThinMaterial)
            
            morphingShape
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.15), Color.black.opacity(0.35)],
                        center: .center,
                        startRadius: 20,
                        endRadius: max(currentWidth, currentHeight) * 0.7
                    )
                )
        }
    }
    
    private var morphingShape: some Shape {
        RoundedRectangle(cornerRadius: cornerRadius)
    }
    
    private var rimLight: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    private var shadowColor: Color {
        switch feedbackState {
        case .success: return .green
        case .capturing: return .orange
        case .idle: return .black
        }
    }
    
    // MARK: - Recording Indicator
    
    private var recordingIndicator: some View {
        HStack {
            Spacer()
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.5)
                        .opacity(0.8)
                )
                .modifier(PulseAnimation())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
    
    // MARK: - Compact Content
    
    private var compactContent: some View {
        HStack(spacing: 12) {
            // Left icon
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to capture")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                if knowledgeBaseService.noteCount > 0 {
                    Text("\(knowledgeBaseService.noteCount) notes captured")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.cyan.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Actions
            compactActions
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var compactActions: some View {
        HStack(spacing: 8) {
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(NotionSchemaState.shared.isComplete ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(NotionSchemaState.shared.isComplete ? "已就绪" : "未配置")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Generate report button (if notes exist)
            if knowledgeBaseService.noteCount > 0 {
                Button(action: {
                    Task { await onGenerateReport?() }
                }) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.cyan)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
                .help("生成报告")
            }
            
            // Close button
            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Input Content (V1.2)
    
    private var inputContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Left icon
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Text input
                NoteTextEditor(
                    text: $userNoteText,
                    placeholder: "Any thoughts?",
                    maxLength: maxNoteLength,
                    isFocused: $isInputFocused,
                    onSubmit: submitNote,
                    onCancel: cancelNote
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 24)
                
                // Character count
                Text("\(userNoteText.count)/\(maxNoteLength)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(userNoteText.count > maxNoteLength * 9 / 10 ? .orange : .white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Note Actions
    
    private func submitNote() {
        let trimmedNote = userNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToSubmit = trimmedNote.isEmpty ? nil : String(trimmedNote.prefix(maxNoteLength))
        
        print("📝 [MorphingHUD] Note submitted: \(noteToSubmit ?? "(empty)")")
        
        // Reset state
        userNoteText = ""
        captureWindowState.exitCaptureWindow()
        isInputFocused = false
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            sizeState = .collapsed
        }
        
        // Notify callback
        onNoteSubmitted?(noteToSubmit)
    }
    
    private func cancelNote() {
        print("📝 [MorphingHUD] Note cancelled")
        
        // Reset state
        userNoteText = ""
        captureWindowState.exitCaptureWindow()
        isInputFocused = false
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            sizeState = .collapsed
        }
        
        // Notify with nil (no note)
        onNoteSubmitted?(nil)
    }
    
    // MARK: - Capture Fly-In Animation
    
    private func captureFlyInOverlay(thumbnail: NSImage) -> some View {
        GeometryReader { geometry in
            let startPoint = CGPoint(x: geometry.size.width / 2, y: -100)
            let endPoint = CGPoint(x: orbSize / 2, y: orbSize / 2)
            
            let currentX = startPoint.x + (endPoint.x - startPoint.x) * flyInProgress
            let currentY = startPoint.y + (endPoint.y - startPoint.y) * flyInProgress
            let currentScale = 1.0 - flyInProgress * 0.8
            
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .cyan.opacity(0.5), radius: 10)
                .scaleEffect(currentScale)
                .position(x: currentX, y: currentY)
                .opacity(1.0 - flyInProgress * 0.5)
        }
    }
    
    private func triggerCaptureAnimation(thumbnail: NSImage?) {
        guard let thumbnail = thumbnail else {
            showSuccessFlash()
            return
        }
        
        capturedThumbnail = thumbnail
        flyInProgress = 0
        showCaptureFlyIn = true
        feedbackState = .capturing
        
        withAnimation(.easeInOut(duration: 0.4)) {
            flyInProgress = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showCaptureFlyIn = false
            capturedThumbnail = nil
            showSuccessFlash()
        }
    }
    
    private func showSuccessFlash() {
        feedbackState = .success
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                feedbackState = .idle
            }
        }
    }
    
    // MARK: - Hover Handling
    
    private func handleHover(_ hovering: Bool) {
        hoverWorkItem?.cancel()
        
        if hovering {
            let workItem = DispatchWorkItem {
                // V1.2: If in capture window, enter input mode instead of compact
                if self.captureWindowState.isInCaptureWindow && self.sizeState == .collapsed {
                    // Notify that we're entering input mode - this cancels the 2s timer
                    self.captureWindowState.enterInputMode()
                    
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        self.sizeState = .input
                    }
                    // Focus the text field after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isInputFocused = true
                    }
                    return
                }
                
                guard self.sizeState == .collapsed else { return }
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self.sizeState = .compact
                }
            }
            hoverWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        } else {
            // V1.2: If in input mode and mouse leaves, cancel note
            if sizeState == .input && captureWindowState.isInInputMode {
                cancelNote()
                return
            }
            
            let workItem = DispatchWorkItem {
                guard self.sizeState == .compact else { return }
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self.sizeState = .collapsed
                }
            }
            hoverWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }
}

// MARK: - Note Text Editor (V1.2)

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxLength: Int
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = NoteNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.9)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.insertionPointColor = NSColor.cyan
        
        // Set placeholder
        textView.placeholderString = placeholder
        
        // Store callbacks
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NoteNSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // Handle focus
        if isFocused.wrappedValue && textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        
        init(_ parent: NoteTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Enforce max length
            if textView.string.count > parent.maxLength {
                textView.string = String(textView.string.prefix(parent.maxLength))
            }
            parent.text = textView.string
        }
    }
}

// Custom NSTextView to handle Enter and ESC keys
class NoteNSTextView: NSTextView {
    var placeholderString: String = ""
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // Ensure cursor is visible
        needsDisplay = true
        return result
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw placeholder if empty
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
            let placeholderRect = NSRect(x: 5, y: 0, width: bounds.width - 10, height: bounds.height)
            placeholderString.draw(in: placeholderRect, withAttributes: attrs)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Enter key (without shift) - submit
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        
        // ESC key - cancel
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        
        super.keyDown(with: event)
    }
}

// MARK: - Pulse Animation Modifier

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Preview

#Preview("Morphing HUD - Orb") {
    let captureService = ScreenCaptureService()
    let llmService = GeminiLLMService()
    return MorphingHUDView(
        knowledgeBaseService: KnowledgeBaseService(llmService: llmService, captureService: captureService),
        connectorService: ConnectorService(captureService: captureService, llmService: llmService)
    )
    .frame(width: 600, height: 500)
    .background(Color.gray.opacity(0.3))
}
