Tech Spec: Intelligent Connector Module (Snapshot-to-Action)
1. Overview
This module implements the "Intelligent Connector" logic. It processes a user screenshot, classifies the intent via VLM (Vision Language Model), and routes the data to external tools using MCP (Model Context Protocol).
Constraint: The UI (Floating Panel) and Screenshot Capture mechanism are already implemented. This spec focuses purely on the Logic Layer (Data, VLM, MCP).
2. Core Data Structures (Swift)
2.1 Input Data (Context)
The raw data captured from the user action.
code
Swift
struct SnapshotContext {
    let id: UUID
    let image: NSImage          // The screenshot pixel data
    let browserURL: URL?        // Optional: URL if captured in a browser
    let timestamp: Date         // When the capture happened
}
2.2 Intent Categories
Mapping the business logic to specific code types.
code
Swift
enum IntentCategory: String, Codable, CaseIterable {
    case calendar = "calendar"   // Meeting / Schedule / Time
    case notion = "notion"       // Article / Note / Knowledge
    case linear = "linear"       // Bug / Error / Ticket
    case design = "design"       // UI Design / Inspiration / Image Asset
    case unknown = "unknown"
}
2.3 VLM Response Model (Structured Output)
The JSON structure we expect the VLM to return.
code
Swift
struct VLMAnalysisResult: Codable {
    let primaryIntent: IntentCategory
    let secondaryIntent: IntentCategory? // For "Top 2" logic
    let confidenceScore: Double          // 0.0 to 1.0
    
    // Extracted Semantic Data (Nullable based on intent)
    let title: String?                   // For Event Title / Ticket Title / Note Title
    let description: String?             // For Ticket Desc / Note Body
    let detectedTime: Date?              // For Calendar
    let requiresImageUpload: Bool        // Logic: True for .linear and .design
    
    // MCP Tool Arguments (Pre-formatted for MCP)
    let suggestedActionPayload: [String: String] 
}
3. VLM Classification Logic (The Brain)
3.1 Prompt Strategy
System Prompt:
You are a semantic router for a macOS productivity tool. Analyze the provided image and metadata (URL).
Classify the user's intent into ONE of these categories:
calendar: Contains dates, times, Zoom links, or chat about scheduling.
notion: Contains text-heavy content, articles, documentation, or generic notes.
linear: Contains software error messages (red text, stack traces), bug reports, or broken UI.
design: Contains beautiful UI, color palettes, or visual inspiration.
Rules:
If linear or design, set requiresImageUpload to true.
Extract key fields (title, time, description).
If the intent is ambiguous, provide a secondaryIntent.
Return purely JSON.
User Prompt Template:
code
Text
[Image Attached]
Browser URL: \(context.browserURL?.absoluteString ?? "None")
Current Date: \(context.timestamp)

Task: Analyze and extract.
4. Business Logic Flow (The Controller)
The logic follows a linear pipeline with a countdown interrupt.
Step 1: Ingestion
Receive SnapshotContext.
Convert NSImage to base64 for API call.
Step 2: VLM Call
Call LLM Service (Placeholder Model) with the Prompt.
Parse JSON into VLMAnalysisResult.
Step 3: Action Preparation (The "Countdown" State)
UI Logic (Existing): Display result.title and result.primaryIntent.
Logic: Start a 3-second timer.
Top 2 Handling: If confidenceScore < 0.8 AND secondaryIntent exists, the UI should present a toggle/choice. Default to primaryIntent.
Step 4: Execution (MCP Routing)
When countdown finishes (and not cancelled):
Branch A: Intent == .calendar
Action: Call CalendarMCP.createEvent.
Payload: Title, Time (Start/End), URL (in notes).
Image: Discard (Not needed).
Branch B: Intent == .notion
Action: Call NotionMCP.createPage.
Payload: Title, Body (Summary + URL).
Image: Discard (Unless user forces save).
Branch C: Intent == .linear (Bug)
Action 1: Upload Image to Host (Need ImageHostService). Get imageURL.
Action 2: Call LinearMCP.createIssue.
Payload: Title (Error summary), Description (Stack trace + context.browserURL + Markdown Image ![bug](imageURL)).
Branch D: Intent == .design
Action 1: Upload Image.
Action 2: Call FigmaMCP.postComment OR NotionMCP.saveToGallery.
Payload: Image URL, Tags.
5. MCP Architecture (Service Layer)
We need a protocol-based approach to mock MCP until the real server connection is established.
code
Swift
// MARK: - MCP Interface
protocol MCPClientProtocol {
    func executeTool(name: String, arguments: [String: Any]) async throws -> String
}

// MARK: - Tool Definitions

struct MCPToolRequest {
    let serverName: String // e.g., "linear", "notion"
    let toolName: String   // e.g., "create_issue"
    let args: [String: Any]
}

// MARK: - Routing Logic
class ActionRouter {
    let mcpClient: MCPClientProtocol
    let imageUploader: ImageUploaderProtocol // Service to host images for Bug/Design
    
    func execute(result: VLMAnalysisResult, context: SnapshotContext) async throws {
        
        var finalArgs = result.suggestedActionPayload
        
        // 1. Handle Image Upload if required
        if result.requiresImageUpload {
            let hostedURL = try await imageUploader.upload(context.image)
            finalArgs["image_url"] = hostedURL.absoluteString
        }
        
        // 2. Inject Browser URL if exists (Context Recovery)
        if let url = context.browserURL {
            finalArgs["source_url"] = url.absoluteString
        }
        
        // 3. Dispatch to specific MCP
        switch result.primaryIntent {
        case .calendar:
            try await mcpClient.executeTool(name: "calendar_create_event", arguments: finalArgs)
            
        case .notion:
            // Logic: Create a page in "Inbox" database
            try await mcpClient.executeTool(name: "notion_create_page", arguments: finalArgs)
            
        case .linear:
            // Logic: Create issue in "Triage" team
            try await mcpClient.executeTool(name: "linear_create_issue", arguments: finalArgs)
            
        case .design:
            // Logic: Save to specific notion database for inspiration
            try await mcpClient.executeTool(name: "notion_save_image", arguments: finalArgs)
            
        case .unknown:
            throw RouterError.intentUnclear
        }
    }
}
6. Error Handling
Define explicit errors for the UI to display.
code
Swift
enum ConnectorError: LocalizedError {
    case vlmParsingFailed
    case mcpConnectionLost(server: String)
    case imageUploadFailed
    case executionTimedOut
    
    var errorDescription: String? {
        switch self {
        case .vlmParsingFailed: return "Could not analyze the screenshot."
        case .mcpConnectionLost(let server): return "Connection to \(server) lost."
        case .imageUploadFailed: return "Failed to upload image asset."
        case .executionTimedOut: return "Action timed out."
        }
    }
}
7. Implementation Steps for Cursor
Define Models: Copy Section 2 into Models.swift.
Implement Service: Create VLMService.swift using the prompt strategy in Section 3. Use a placeholder LLMClient.complete(prompt:) function.
Implement Router: Copy Section 5 into ActionRouter.swift.
Wire Up: connect the existing floating panel's "Screenshot Taken" event to ActionRouter.execute().
Note to Cursor:
Assume ImageUploaderProtocol returns a public URL string.
Assume LLMClient is a generic wrapper for whichever model API is chosen later.
Focus on robust JSON parsing from the VLM response, as LLMs can sometimes output markdown fences (```json). Strip those before parsing.