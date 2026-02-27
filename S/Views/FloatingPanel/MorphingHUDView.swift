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
    
    // Layout constants - Card style (Digital Stationery)
    private let collapsedSize: CGFloat = 48
    private let compactWidth: CGFloat = 280
    private let compactHeight: CGFloat = 64
    private let inputWidth: CGFloat = 300
    private let inputBaseHeight: CGFloat = 72
    private let maxNoteLength: Int = 1000
    
    // MARK: - Computed Properties
    
    private var currentWidth: CGFloat {
        switch sizeState {
        case .collapsed: return collapsedSize
        case .compact: return compactWidth
        case .input: return inputWidth
        }
    }
    
    private var currentHeight: CGFloat {
        switch sizeState {
        case .collapsed: return collapsedSize
        case .compact: return compactHeight
        case .input: return calculatedInputHeight
        }
    }
    
    private var calculatedInputHeight: CGFloat {
        // Dynamic height based on text content - unfold animation
        let lineCount = max(1, userNoteText.components(separatedBy: "\n").count)
        let estimatedLines = max(lineCount, Int(ceil(Double(userNoteText.count) / 35.0)))
        let clampedLines = min(max(1, estimatedLines), 5)
        return inputBaseHeight + CGFloat(clampedLines - 1) * 22
    }
    
    private var cornerRadius: CGFloat {
        switch sizeState {
        case .collapsed: return CardDesign.collapsedCornerRadius
        case .compact, .input: return CardDesign.expandedCornerRadius
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
                cardBackground
                compactContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
                
            case .input:
                cardBackground
                inputContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Fly-in thumbnail overlay (during capture)
            if showCaptureFlyIn, let thumbnail = capturedThumbnail {
                captureFlyInOverlay(thumbnail: thumbnail)
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .contentShape(morphingShape)
        .clipShape(morphingShape)
        .overlay(cardBorder)
        .shadow(color: CardDesign.shadowColor, radius: CardDesign.shadowRadius, x: 0, y: CardDesign.shadowY)
        .background(Color.clear)
        .onHover(perform: handleHover)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sizeState)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: feedbackState)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: calculatedInputHeight)
        .onReceive(knowledgeBaseService.$lastCaptureEvent) { event in
            if let event = event {
                triggerCaptureAnimation(thumbnail: event.thumbnail)
            }
        }
    }
    
    // MARK: - Card Background (Digital Stationery)
    
    private var cardBackground: some View {
        morphingShape
            .fill(CardDesign.cardBackground)
    }
    
    private var morphingShape: some Shape {
        RoundedRectangle(cornerRadius: cornerRadius)
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(CardDesign.border, lineWidth: 1)
    }
    
    // MARK: - Compact Content (Digital Stationery Card)
    
    private var compactContent: some View {
        HStack(spacing: 14) {
            // Left side - status info
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(CardDesign.textPrimary)
                
                if knowledgeBaseService.noteCount > 0 {
                    Text("\(knowledgeBaseService.noteCount) notes")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(CardDesign.textSecondary)
                }
            }
            
            Spacer()
            
            // Actions
            compactActions
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var compactActions: some View {
        HStack(spacing: 10) {
            // Status indicator - minimal pill style
            HStack(spacing: 5) {
                Circle()
                    .fill(NotionSchemaState.shared.isComplete ? CardDesign.successGreen : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(NotionSchemaState.shared.isComplete ? "已就绪" : "未配置")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CardDesign.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(hex: "F5F5F5"))
            )
            
            // Generate report button (if notes exist)
            if knowledgeBaseService.noteCount > 0 {
                Button(action: {
                    Task { await onGenerateReport?() }
                }) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CardDesign.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color(hex: "F5F5F5"))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("生成报告")
            }
            
            // Close button - minimal
            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CardDesign.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color(hex: "F5F5F5"))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Input Content (Digital Stationery - No Input Field Feel)
    
    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with character count
            HStack {
                Text("Note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CardDesign.textSecondary)
                
                Spacer()
                
                // Character count - subtle
                Text("\(userNoteText.count)/\(maxNoteLength)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(userNoteText.count > maxNoteLength * 9 / 10 ? .orange : CardDesign.textSecondary.opacity(0.6))
            }
            
            // Text input - no visible input field, writes directly on card
            NoteTextEditor(
                text: $userNoteText,
                placeholder: "Any thoughts?",
                maxLength: maxNoteLength,
                isFocused: $isInputFocused,
                onSubmit: submitNote,
                onCancel: cancelNote
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 28)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
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
            let startPoint = CGPoint(x: geometry.size.width / 2, y: -80)
            let endPoint = CGPoint(x: collapsedSize / 2, y: collapsedSize / 2)
            
            let currentX = startPoint.x + (endPoint.x - startPoint.x) * flyInProgress
            let currentY = startPoint.y + (endPoint.y - startPoint.y) * flyInProgress
            let currentScale = 1.0 - flyInProgress * 0.75
            
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(CardDesign.border, lineWidth: 1)
                )
                .shadow(color: CardDesign.shadowColor, radius: 8)
                .scaleEffect(currentScale)
                .position(x: currentX, y: currentY)
                .opacity(1.0 - flyInProgress * 0.4)
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
        // Digital Stationery: Serif font for text content
        textView.font = NSFont(name: "Georgia", size: 14) ?? NSFont.systemFont(ofSize: 14, weight: .regular)
        // Dark text on white card background
        textView.textColor = NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0) // #111111
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        // Subtle insertion point color
        textView.insertionPointColor = NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 0.8)
        
        // Set placeholder
        textView.placeholderString = placeholder
        
        // Store callbacks
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        
        scrollView.documentView = textView
        
        // Auto-focus when view appears - use async to ensure window is ready
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NoteNSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // Handle focus - try multiple times to ensure focus is set
        if isFocused.wrappedValue && textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
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
        
        // Draw placeholder if empty - Digital Stationery style
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 0.4), // Subtle dark placeholder
                .font: NSFont(name: "Georgia", size: 14) ?? NSFont.systemFont(ofSize: 14, weight: .regular)
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
