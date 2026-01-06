import Foundation
import AppKit

// MARK: - Intelligent Connector Data Models
// Implements: Snapshot-to-Action pipeline for VLM intent classification and MCP routing

// MARK: - Input Data (Context)

/// Raw data captured from user action
struct SnapshotContext: Sendable {
    let id: UUID
    let image: NSImage
    let browserURL: URL?
    let timestamp: Date
    
    init(id: UUID = UUID(), image: NSImage, browserURL: URL? = nil, timestamp: Date = Date()) {
        self.id = id
        self.image = image
        self.browserURL = browserURL
        self.timestamp = timestamp
    }
}

// MARK: - Intent Categories

/// Business logic intent classification
enum IntentCategory: String, Codable, CaseIterable, Sendable {
    case calendar = "calendar"   // Meeting / Schedule / Time
    case notion = "notion"       // Article / Note / Knowledge
    case linear = "linear"       // Bug / Error / Ticket
    case design = "design"       // UI Design / Inspiration / Image Asset
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .calendar: return "Calendar"
        case .notion: return "Notion"
        case .linear: return "Linear"
        case .design: return "Design"
        case .unknown: return "Unknown"
        }
    }
    
    var icon: String {
        switch self {
        case .calendar: return "📅"
        case .notion: return "📝"
        case .linear: return "🐛"
        case .design: return "🎨"
        case .unknown: return "❓"
        }
    }
}

// MARK: - VLM Response Model

/// Structured output from VLM analysis
struct VLMAnalysisResult: Codable, Sendable {
    let primaryIntent: IntentCategory
    let secondaryIntent: IntentCategory?
    let confidenceScore: Double
    
    // Extracted Semantic Data
    let title: String?
    let description: String?
    let detectedTime: Date?
    let requiresImageUpload: Bool
    
    // MCP Tool Arguments (Pre-formatted)
    let suggestedActionPayload: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case primaryIntent = "primary_intent"
        case secondaryIntent = "secondary_intent"
        case confidenceScore = "confidence_score"
        case title
        case description
        case detectedTime = "detected_time"
        case requiresImageUpload = "requires_image_upload"
        case suggestedActionPayload = "suggested_action_payload"
    }
    
    /// Check if intent is ambiguous (needs user confirmation)
    var isAmbiguous: Bool {
        confidenceScore < 0.8 && secondaryIntent != nil
    }
}

// MARK: - Connector Errors

enum ConnectorError: LocalizedError, Sendable {
    case vlmParsingFailed
    case mcpConnectionLost(server: String)
    case imageUploadFailed
    case executionTimedOut
    case noImageAvailable
    case invalidResponse
    case authenticationRequired
    case toolNotFound(name: String)
    
    var errorDescription: String? {
        switch self {
        case .vlmParsingFailed:
            return "Could not analyze the screenshot."
        case .mcpConnectionLost(let server):
            return "Connection to \(server) lost."
        case .imageUploadFailed:
            return "Failed to upload image asset."
        case .executionTimedOut:
            return "Action timed out."
        case .noImageAvailable:
            return "No screenshot available."
        case .invalidResponse:
            return "Invalid response from server."
        case .authenticationRequired:
            return "Authentication required. Please connect your account."
        case .toolNotFound(let name):
            return "Tool '\(name)' not found on MCP server."
        }
    }
}

// MARK: - Router Errors

enum RouterError: LocalizedError, Sendable {
    case intentUnclear
    case mcpNotConfigured(intent: IntentCategory)
    case executionFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .intentUnclear:
            return "Could not determine user intent."
        case .mcpNotConfigured(let intent):
            return "No MCP configured for \(intent.displayName)."
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        }
    }
}
