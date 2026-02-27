import Foundation
import AppKit
import Combine

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a capture event is triggered (for showing floating panel)
    static let captureEventTriggered = Notification.Name("captureEventTriggered")
}

/// V9: Knowledge Base Service for Visual Note management
/// Implements "Capture to Log" workflow with ephemeral image processing
@MainActor
final class KnowledgeBaseService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var notes: [VisualNote] = []
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastError: String?
    
    // V10: Capture event for fly-in animation
    @Published var lastCaptureEvent: CaptureEvent?
    
    // V1.2: Pending screenshot for delayed processing with user note
    private var pendingScreenshot: NSImage?
    
    // MARK: - Dependencies
    
    private let llmService: GeminiLLMService
    private let captureService: ScreenCaptureService
    private let notionAPI: NotionAPIClient
    
    // V1.1: Pipeline controller for Visual ETL
    let pipelineController: PipelineController
    
    // MARK: - Computed Properties
    
    var noteCount: Int { notes.count }
    var isEmpty: Bool { notes.isEmpty }
    
    // MARK: - Initialization
    
    init(llmService: GeminiLLMService = GeminiLLMService(), captureService: ScreenCaptureService) {
        self.llmService = llmService
        self.captureService = captureService
        self.notionAPI = NotionAPIClient.shared
        self.pipelineController = PipelineController(llmService: llmService, captureService: captureService)
    }
    
    // MARK: - Public Methods
    
    /// Capture current screen and store for delayed processing
    /// V1.2: Split into capture phase (immediate) and processing phase (after note input)
    /// Per v9.md Section 3: Ephemeral Image Processing
    /// V10: Publishes capture event for fly-in animation
    func captureVisualNote() async {
        print("📸 [KnowledgeBase] Starting visual note capture...")
        isProcessing = true
        lastError = nil
        
        // Play capture sound effect
        SoundEffectService.shared.playCaptureSound()
        
        // Post notification to show floating panel near cursor
        NotificationCenter.default.post(name: .captureEventTriggered, object: nil)
        
        do {
            // Step 1: Capture full screen
            await captureService.captureScreen()
            
            guard let screenshot = captureService.currentScreenshot else {
                throw KnowledgeBaseError.captureFailure("No screenshot available")
            }
            
            // V1.2: Store screenshot for delayed processing
            pendingScreenshot = screenshot
            
            // V10: Publish capture event immediately for fly-in animation
            let thumbnail = createThumbnail(from: screenshot, size: CGSize(width: 120, height: 80))
            lastCaptureEvent = CaptureEvent(thumbnail: thumbnail)
            
            print("📸 [KnowledgeBase] Screenshot captured, waiting for note input...")
            
            // V1.2: Processing is now triggered by processCapture(withUserNote:)
            // after the capture window expires or user submits a note
            
        } catch {
            lastError = error.localizedDescription
            print("❌ [KnowledgeBase] Capture failed: \(error)")
            isProcessing = false
        }
    }
    
    /// Process the captured screenshot with optional user note
    /// V1.2: Called after capture window expires or user submits note
    func processCapture(withUserNote userNote: String?) async {
        guard let screenshot = pendingScreenshot else {
            print("⚠️ [KnowledgeBase] No pending screenshot to process")
            isProcessing = false
            return
        }
        
        // Clear pending screenshot
        pendingScreenshot = nil
        
        print("📸 [KnowledgeBase] Processing capture with note: \(userNote ?? "(none)")")
        
        do {
            // Step 2: Compress/resize for API (reduce to reasonable size)
            let resizedImage = resizeImageForAPI(screenshot, maxDimension: 1024)
            
            // Step 3: Analyze with VLM
            let analysis = try await analyzeWithVLM(resizedImage)
            
            // Step 4: Store text metadata only (image is destroyed after this)
            let note = VisualNote(
                caption: analysis.caption,
                intent: analysis.intent
            )
            notes.append(note)
            
            print("📸 [KnowledgeBase] Visual note stored: \(analysis.caption.prefix(50))...")
            print("📸 [KnowledgeBase] Total notes: \(notes.count)")
            
            // Step 5: V1.1 - Use Pipeline for structured ETL if schema is configured
            // V1.2: Pass user note to pipeline
            // Otherwise fall back to legacy saveToNotionIfConfigured
            if NotionSchemaState.shared.isComplete {
                // Use V1.1 Visual ETL Pipeline with user note
                let _ = await pipelineController.execute(screenshot: screenshot, userNote: userNote)
            } else {
                // Legacy: Save to configured target
                await saveToNotionIfConfigured(note: note)
            }
            
            // Image data is now out of scope and will be garbage collected
            // No disk write occurs
            
        } catch {
            lastError = error.localizedDescription
            print("❌ [KnowledgeBase] Processing failed: \(error)")
        }
        
        isProcessing = false
    }
    
    /// Add a note from external analysis (for testing or manual input)
    func addNote(caption: String, intent: String) {
        let note = VisualNote(caption: caption, intent: intent)
        notes.append(note)
        print("📸 [KnowledgeBase] Note added manually, total: \(notes.count)")
    }
    
    /// Clear all collected notes
    func clearAll() {
        notes.removeAll()
        print("📸 [KnowledgeBase] All notes cleared")
    }
    
    /// Generate a knowledge report from collected notes
    /// Per v9.md Section 5: Smart Report Generation
    func generateReport() async throws -> String {
        guard !notes.isEmpty else {
            throw KnowledgeBaseError.emptyNotes
        }
        
        print("📝 [KnowledgeBase] Generating report from \(notes.count) notes...")
        isProcessing = true
        
        defer { isProcessing = false }
        
        // Build input for synthesis
        let notesInput = notes.enumerated().map { index, note in
            """
            Note \(index + 1) [\(formatDate(note.timestamp))]:
            - Caption: \(note.caption)
            - Intent: \(note.intent)
            """
        }.joined(separator: "\n\n")
        
        let timeRange = formatTimeRange()
        
        let prompt = """
        [TASK]
        Synthesize these visual notes into a coherent Knowledge Report.
        The user captured these screenshots in sequence.
        Group them logically (e.g., "Design Inspiration", "Code Snippets").
        Deduplicate if multiple notes seem to describe the same static screen.
        
        [NOTES]
        \(notesInput)
        
        [TIME RANGE]
        \(timeRange)
        
        [OUTPUT FORMAT]
        Markdown.
        Structure:
        # Visual Session Report [Date]
        ## Summary
        ...
        ## Key Insights
        - [Intent]: [Caption details]
        ...
        
        Return ONLY the markdown report, no JSON wrapper.
        """
        
        guard let report = await llmService.generateText(prompt: prompt, systemPrompt: nil) else {
            throw KnowledgeBaseError.reportGenerationFailed
        }
        
        print("📝 [KnowledgeBase] Report generated successfully")
        return report
    }
    
    /// Generate report and copy to clipboard
    /// Per v9.md Section 5.3: Output Action
    func generateReportAndCopy() async throws {
        let report = try await generateReport()
        
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        
        print("📋 [KnowledgeBase] Report copied to clipboard!")
    }
    
    // MARK: - Notion Integration
    
    /// Save note to Notion if connected and target is configured
    private func saveToNotionIfConfigured(note: VisualNote) async {
        let settings = MCPSettings.shared
        let oauthService = NotionOAuth2Service.shared
        
        // Check if Notion is connected and target is configured
        guard oauthService.isAuthenticated else {
            print("📝 [KnowledgeBase] Notion not connected, skipping sync")
            return
        }
        
        guard settings.hasNotionTarget else {
            print("📝 [KnowledgeBase] No Notion target configured, skipping sync")
            return
        }
        
        print("📝 [KnowledgeBase] Saving to Notion...")
        
        do {
            let title = "Visual Note - \(formatDate(note.timestamp))"
            let content = """
            **Caption:** \(note.caption)
            
            **Intent:** \(note.intent)
            
            ---
            *Captured at \(formatDate(note.timestamp))*
            """
            
            let pageId = try await notionAPI.saveVLMAnalysisResult(
                title: title,
                content: content,
                category: note.intent,
                confidence: 1.0
            )
            
            print("✅ [KnowledgeBase] Saved to Notion: \(pageId)")
        } catch {
            print("❌ [KnowledgeBase] Failed to save to Notion: \(error)")
            // Don't fail the whole operation, just log the error
        }
    }
    
    // MARK: - Private Methods
    
    /// Analyze screenshot with VLM to extract caption and intent
    private func analyzeWithVLM(_ image: NSImage) async throws -> VisualNoteAnalysis {
        let prompt = """
        [TASK]
        Analyze this screenshot for a Personal Knowledge Base.
        The user saved this because they found it interesting or useful.
        
        [OUTPUT JSON]
        {
          "caption": "Brief description of the content (e.g., A Python script for web scraping using BeautifulSoup).",
          "intent": "Why the user saved this (e.g., Reference for future coding, UI design inspiration, error log)."
        }
        
        IMPORTANT: Return ONLY valid JSON, no other text.
        """
        
        guard let response = await llmService.analyzeImage(image, prompt: prompt) else {
            throw KnowledgeBaseError.vlmAnalysisFailed
        }
        
        // Parse JSON response
        let cleanedResponse = extractJSON(from: response)
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw KnowledgeBaseError.invalidResponse
        }
        
        return try JSONDecoder().decode(VisualNoteAnalysis.self, from: data)
    }
    
    /// Resize image for API efficiency
    private func resizeImageForAPI(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        
        // Only resize if larger than max dimension
        if ratio >= 1.0 {
            return image
        }
        
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// V10: Create thumbnail for fly-in animation
    private func createThumbnail(from image: NSImage, size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Extract JSON from response text
    private func extractJSON(from text: String) -> String {
        if let jsonStart = text.range(of: "{"),
           let jsonEnd = text.range(of: "}", options: .backwards),
           jsonStart.lowerBound < jsonEnd.lowerBound {
            let endIndex = text.index(after: jsonEnd.lowerBound)
            return String(text[jsonStart.lowerBound..<endIndex])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Format date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    /// Format time range of notes
    private func formatTimeRange() -> String {
        guard let first = notes.first, let last = notes.last else {
            return "N/A"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        return "\(formatter.string(from: first.timestamp)) - \(formatter.string(from: last.timestamp))"
    }
}

// MARK: - Errors

enum KnowledgeBaseError: LocalizedError {
    case captureFailure(String)
    case vlmAnalysisFailed
    case invalidResponse
    case emptyNotes
    case reportGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .captureFailure(let reason):
            return "Screen capture failed: \(reason)"
        case .vlmAnalysisFailed:
            return "VLM analysis failed"
        case .invalidResponse:
            return "Invalid response from VLM"
        case .emptyNotes:
            return "No notes to generate report from"
        case .reportGenerationFailed:
            return "Failed to generate report"
        }
    }
}
