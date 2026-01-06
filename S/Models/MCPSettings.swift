import Foundation

// MARK: - MCP Settings
// Stores user configuration for MCP connections

@MainActor
@Observable
final class MCPSettings {
    
    // MARK: - Singleton
    
    static let shared = MCPSettings()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let notionConnected = "mcp.notion.connected"
        static let notionApiToken = "mcp.notion.apiToken"
        static let notionTargetPageId = "mcp.notion.targetPageId"
        static let notionTargetPageTitle = "mcp.notion.targetPageTitle"
        static let notionTargetDatabaseId = "mcp.notion.targetDatabaseId"
        static let notionTargetDatabaseTitle = "mcp.notion.targetDatabaseTitle"
    }
    
    // MARK: - Notion Settings
    
    /// Whether Notion MCP is connected (has valid token)
    var isNotionConnected: Bool {
        didSet {
            UserDefaults.standard.set(isNotionConnected, forKey: Keys.notionConnected)
        }
    }
    
    /// Notion API token (Internal Integration Token: ntn_xxx)
    var notionApiToken: String? {
        didSet {
            if let token = notionApiToken {
                UserDefaults.standard.set(token, forKey: Keys.notionApiToken)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.notionApiToken)
            }
        }
    }
    
    /// Target page ID for saving notes
    var notionTargetPageId: String? {
        didSet {
            UserDefaults.standard.set(notionTargetPageId, forKey: Keys.notionTargetPageId)
        }
    }
    
    /// Target page title (for display)
    var notionTargetPageTitle: String? {
        didSet {
            UserDefaults.standard.set(notionTargetPageTitle, forKey: Keys.notionTargetPageTitle)
        }
    }
    
    /// Target database ID for saving notes
    var notionTargetDatabaseId: String? {
        didSet {
            UserDefaults.standard.set(notionTargetDatabaseId, forKey: Keys.notionTargetDatabaseId)
        }
    }
    
    /// Target database title (for display)
    var notionTargetDatabaseTitle: String? {
        didSet {
            UserDefaults.standard.set(notionTargetDatabaseTitle, forKey: Keys.notionTargetDatabaseTitle)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Display name for current target
    var notionTargetDisplayName: String {
        if let title = notionTargetDatabaseTitle {
            return "📊 \(title)"
        } else if let title = notionTargetPageTitle {
            return "📄 \(title)"
        } else {
            return "未设置"
        }
    }
    
    /// Whether a target is configured
    var hasNotionTarget: Bool {
        notionTargetPageId != nil || notionTargetDatabaseId != nil
    }
    
    // MARK: - Initialization
    
    private init() {
        self.isNotionConnected = UserDefaults.standard.bool(forKey: Keys.notionConnected)
        self.notionApiToken = UserDefaults.standard.string(forKey: Keys.notionApiToken)
        self.notionTargetPageId = UserDefaults.standard.string(forKey: Keys.notionTargetPageId)
        self.notionTargetPageTitle = UserDefaults.standard.string(forKey: Keys.notionTargetPageTitle)
        self.notionTargetDatabaseId = UserDefaults.standard.string(forKey: Keys.notionTargetDatabaseId)
        self.notionTargetDatabaseTitle = UserDefaults.standard.string(forKey: Keys.notionTargetDatabaseTitle)
    }
    
    // MARK: - Methods
    
    /// Clear all Notion settings
    func clearNotionSettings() {
        isNotionConnected = false
        notionApiToken = nil
        notionTargetPageId = nil
        notionTargetPageTitle = nil
        notionTargetDatabaseId = nil
        notionTargetDatabaseTitle = nil
    }
    
    /// Set Notion API token and mark as connected
    func setNotionToken(_ token: String) {
        notionApiToken = token
        isNotionConnected = true
    }
    
    /// Set target page
    func setNotionTargetPage(id: String, title: String) {
        notionTargetPageId = id
        notionTargetPageTitle = title
        notionTargetDatabaseId = nil
        notionTargetDatabaseTitle = nil
    }
    
    /// Set target database
    func setNotionTargetDatabase(id: String, title: String) {
        notionTargetDatabaseId = id
        notionTargetDatabaseTitle = title
        notionTargetPageId = nil
        notionTargetPageTitle = nil
    }
}

// MARK: - Notion Page/Database Info

struct NotionPageInfo: Identifiable, Sendable {
    let id: String
    let title: String
    let icon: String?
    let isDatabase: Bool
    
    var displayIcon: String {
        if let icon = icon {
            return icon
        }
        return isDatabase ? "📊" : "📄"
    }
}
