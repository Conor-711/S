import Foundation
import AppKit

// MARK: - V1.1 Visual ETL Pipeline Controller
// Orchestrates: Capture -> Atomize -> Fit -> Notion/Slack
// V1.2: Routes work todos to Slack, life todos to Notion

@MainActor
final class PipelineController: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastAtom: Atom?
    
    // MARK: - Dependencies
    
    private let llmService: GeminiLLMService
    private let captureService: ScreenCaptureService
    private let notionAPI: NotionAPIClient
    private let schemaState: NotionSchemaState
    
    // MARK: - Initialization
    
    init(llmService: GeminiLLMService, captureService: ScreenCaptureService) {
        self.llmService = llmService
        self.captureService = captureService
        self.notionAPI = NotionAPIClient.shared
        self.schemaState = NotionSchemaState.shared
    }
    
    // MARK: - Schema Initialization
    
    /// Initialize Notion schema: Create "S" page and databases
    /// Creates page at workspace level (under first available page)
    func initializeSchema() async throws {
        print("🔧 [Pipeline] Creating ETL schema at workspace level...")
        
        // Step 1: Create new "S" page
        let sPageId = try await notionAPI.createETLRootPage(title: "S")
        
        // Step 2: Create Content Database inside "S" page
        let contentDbId = try await notionAPI.createContentDatabase(parentPageId: sPageId)
        
        // Step 3: Create Todo Database inside "S" page
        let todoDbId = try await notionAPI.createTodoDatabase(parentPageId: sPageId)
        
        // Step 4: Save to state
        schemaState.setRootPage(id: sPageId, title: "S")
        schemaState.setDatabases(contentId: contentDbId, todoId: todoDbId)
        
        print("✅ [Pipeline] Schema initialized successfully - S Page: \(sPageId)")
    }
    
    /// Initialize Notion schema inside a specific parent page
    func initializeSchema(parentPageId: String) async throws {
        print("🔧 [Pipeline] Creating ETL schema in parent page: \(parentPageId)")
        
        // Step 1: Create new "S" page inside the selected parent
        let sPageId = try await notionAPI.createETLRootPage(parentPageId: parentPageId, title: "S")
        
        // Step 2: Create Content Database inside "S" page
        let contentDbId = try await notionAPI.createContentDatabase(parentPageId: sPageId)
        
        // Step 3: Create Todo Database inside "S" page
        let todoDbId = try await notionAPI.createTodoDatabase(parentPageId: sPageId)
        
        // Step 4: Save to state
        schemaState.setRootPage(id: sPageId, title: "S")
        schemaState.setDatabases(contentId: contentDbId, todoId: todoDbId)
        
        print("✅ [Pipeline] Schema initialized successfully - S Page: \(sPageId)")
    }
    
    // MARK: - Main Pipeline
    
    /// Execute the full ETL pipeline: Capture -> Atomize -> Fit -> Notion
    /// V1.2: Now accepts optional user note for AI enhancement
    /// V1.2: Added retry mechanism (max 3 attempts) for network errors
    /// Returns the created Notion page ID, or nil if discarded
    func execute(screenshot: NSImage, userNote: String? = nil) async -> String? {
        guard schemaState.isComplete else {
            print("⚠️ [Pipeline] Schema not configured, skipping Notion sync")
            lastError = "Schema not configured"
            return nil
        }
        
        guard NotionOAuth2Service.shared.isAuthenticated else {
            print("⚠️ [Pipeline] Not authenticated with Notion")
            lastError = "Not authenticated"
            return nil
        }
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                // Step 1: Atomize - VLM analysis with optional user note
                print("🧠 [Pipeline] Atomizing screenshot\(userNote != nil ? " with user note" : "")... (attempt \(attempt)/\(maxRetries))")
                let atom = try await atomize(screenshot: screenshot, userNote: userNote)
                lastAtom = atom
                
                // Step 2: Filter - Check if discard
                if atom.type == .discard {
                    print("🗑️ [Pipeline] Content discarded by VLM")
                    return nil
                }
                
                // Step 3: Fit & Execute - Save to appropriate database
                print("💾 [Pipeline] Saving to destination...")
                let pageId = try await fit(atom: atom)
                
                print("✅ [Pipeline] Saved successfully: \(pageId)")
                return pageId
                
            } catch let error as NSError {
                lastError = error
                
                // Check if it's a retryable network error
                if isRetryableError(error) && attempt < maxRetries {
                    let delay = Double(attempt) * 1.0  // 1s, 2s, 3s backoff
                    print("⚠️ [Pipeline] Network error (attempt \(attempt)/\(maxRetries)), retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    self.lastError = error.localizedDescription
                    print("❌ [Pipeline] Pipeline failed after \(attempt) attempt(s): \(error)")
                    return nil
                }
            } catch {
                self.lastError = error.localizedDescription
                print("❌ [Pipeline] Pipeline failed: \(error)")
                return nil
            }
        }
        
        self.lastError = lastError?.localizedDescription ?? "Unknown error after retries"
        return nil
    }
    
    /// Check if an error is retryable (network-related)
    private func isRetryableError(_ error: NSError) -> Bool {
        // NSURLErrorDomain errors that are typically transient
        let retryableCodes: Set<Int> = [
            -1001, // NSURLErrorTimedOut
            -1005, // NSURLErrorNetworkConnectionLost
            -1009, // NSURLErrorNotConnectedToInternet
            -1004, // NSURLErrorCannotConnectToHost
            -1003, // NSURLErrorCannotFindHost
        ]
        
        if error.domain == NSURLErrorDomain && retryableCodes.contains(error.code) {
            return true
        }
        
        return false
    }
    
    // MARK: - Pipeline Steps
    
    /// Atomize: Analyze screenshot with VLM and extract structured data
    /// V1.2: Now accepts optional user note for AI enhancement
    private func atomize(screenshot: NSImage, userNote: String? = nil) async throws -> Atom {
        // Get current date for relative time calculation
        let dateFormatter = ISO8601DateFormatter()
        let currentDate = dateFormatter.string(from: Date())
        
        // Build prompt with current date and optional user note
        let prompt = AgentPrompts.visualETLPrompt(currentDate: currentDate, userNote: userNote)
        
        // Resize image for API
        let resizedImage = resizeImageForAPI(screenshot, maxDimension: 1024)
        
        // Call VLM
        guard let response = await llmService.analyzeImage(resizedImage, prompt: prompt) else {
            throw PipelineError.vlmAnalysisFailed
        }
        
        // Parse JSON response
        let cleanedResponse = extractJSON(from: response)
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw PipelineError.invalidResponse
        }
        
        // Decode to VLM response model
        let vlmResponse = try JSONDecoder().decode(AtomVLMResponse.self, from: data)
        
        // Convert to Atom with validation
        guard let atom = vlmResponse.toAtom() else {
            throw PipelineError.invalidAtom
        }
        
        print("🧠 [Pipeline] Atomized: type=\(atom.type.rawValue), title=\(atom.payload.title.prefix(50))...")
        if let note = atom.payload.userNote {
            print("🧠 [Pipeline] Enhanced note: \(note.prefix(50))...")
        }
        return atom
    }
    
    /// Fit: Map Atom to appropriate destination and save
    /// V1.2: Routes work todos to Slack, life todos and content to Notion
    private func fit(atom: Atom) async throws -> String {
        switch atom.type {
        case .content:
            guard let dbId = schemaState.contentDbId else {
                throw PipelineError.databaseNotConfigured
            }
            return try await notionAPI.saveContentAtom(atom.payload, toDatabaseId: dbId)
            
        case .todo:
            // V1.2: Route based on todo context
            if atom.payload.isWorkTodo && SlackOAuthService.shared.isAuthenticated {
                // Work todo -> Slack
                print("📤 [Pipeline] Routing work todo to Slack...")
                let success = await SlackOAuthService.shared.postWorkTodo(
                    title: atom.payload.title,
                    description: atom.payload.description,
                    assignee: atom.payload.assigneeName,
                    dueDate: atom.payload.dueDate,
                    userNote: atom.payload.userNote
                )
                if success {
                    return "slack-message-sent"
                } else {
                    throw PipelineError.slackPostFailed
                }
            } else {
                // Life todo or no Slack connection -> Notion
                guard let dbId = schemaState.todoDbId else {
                    throw PipelineError.databaseNotConfigured
                }
                return try await notionAPI.saveTodoAtom(atom.payload, toDatabaseId: dbId)
            }
            
        case .discard:
            throw PipelineError.discardedContent
        }
    }
    
    // MARK: - Helper Methods
    
    /// Resize image for API efficiency
    private func resizeImageForAPI(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        
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
}

// MARK: - Pipeline Errors

enum PipelineError: LocalizedError {
    case noRootPageSelected
    case databaseNotConfigured
    case vlmAnalysisFailed
    case invalidResponse
    case invalidAtom
    case discardedContent
    case notionSaveFailed(String)
    case slackPostFailed  // V1.2
    
    var errorDescription: String? {
        switch self {
        case .noRootPageSelected:
            return "请先选择根页面"
        case .databaseNotConfigured:
            return "数据库未配置，请先初始化"
        case .vlmAnalysisFailed:
            return "VLM 分析失败"
        case .invalidResponse:
            return "无效的 VLM 响应"
        case .invalidAtom:
            return "无法解析分析结果"
        case .discardedContent:
            return "内容被丢弃"
        case .notionSaveFailed(let reason):
            return "保存到 Notion 失败: \(reason)"
        case .slackPostFailed:
            return "发送到 Slack 失败"
        }
    }
}
