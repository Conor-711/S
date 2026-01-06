import Foundation

// MARK: - V1.1 Notion Schema State
// Stores Notion database IDs for Visual ETL pipeline

@MainActor
@Observable
final class NotionSchemaState {
    
    // MARK: - Singleton
    
    static let shared = NotionSchemaState()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let rootPageId = "notion.schema.rootPageId"
        static let rootPageTitle = "notion.schema.rootPageTitle"
        static let contentDbId = "notion.schema.contentDbId"
        static let todoDbId = "notion.schema.todoDbId"
        static let isInitialized = "notion.schema.isInitialized"
    }
    
    // MARK: - Properties
    
    /// Root page ID (Page "S" selected by user)
    var rootPageId: String? {
        didSet {
            if let id = rootPageId {
                UserDefaults.standard.set(id, forKey: Keys.rootPageId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.rootPageId)
            }
        }
    }
    
    /// Root page title (for display)
    var rootPageTitle: String? {
        didSet {
            if let title = rootPageTitle {
                UserDefaults.standard.set(title, forKey: Keys.rootPageTitle)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.rootPageTitle)
            }
        }
    }
    
    /// Content Database ID (Visual Knowledge)
    var contentDbId: String? {
        didSet {
            if let id = contentDbId {
                UserDefaults.standard.set(id, forKey: Keys.contentDbId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.contentDbId)
            }
        }
    }
    
    /// To-do Database ID (Visual Tasks)
    var todoDbId: String? {
        didSet {
            if let id = todoDbId {
                UserDefaults.standard.set(id, forKey: Keys.todoDbId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.todoDbId)
            }
        }
    }
    
    /// Whether the schema has been initialized
    var isInitialized: Bool {
        didSet {
            UserDefaults.standard.set(isInitialized, forKey: Keys.isInitialized)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether all required IDs are present
    var isComplete: Bool {
        rootPageId != nil && contentDbId != nil && todoDbId != nil
    }
    
    /// Whether root page is selected but databases not created
    var needsDatabaseCreation: Bool {
        rootPageId != nil && (contentDbId == nil || todoDbId == nil)
    }
    
    /// Display status
    var statusDescription: String {
        if isComplete {
            return "✅ 已配置"
        } else if rootPageId != nil {
            return "⚠️ 需要创建数据库"
        } else {
            return "❌ 未配置"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        self.rootPageId = UserDefaults.standard.string(forKey: Keys.rootPageId)
        self.rootPageTitle = UserDefaults.standard.string(forKey: Keys.rootPageTitle)
        self.contentDbId = UserDefaults.standard.string(forKey: Keys.contentDbId)
        self.todoDbId = UserDefaults.standard.string(forKey: Keys.todoDbId)
        self.isInitialized = UserDefaults.standard.bool(forKey: Keys.isInitialized)
    }
    
    // MARK: - Methods
    
    /// Set root page (user selected)
    func setRootPage(id: String, title: String) {
        rootPageId = id
        rootPageTitle = title
        // Clear database IDs when root page changes
        contentDbId = nil
        todoDbId = nil
        isInitialized = false
        print("📝 [NotionSchema] Root page set: \(title) (\(id))")
    }
    
    /// Set database IDs after creation
    func setDatabases(contentId: String, todoId: String) {
        contentDbId = contentId
        todoDbId = todoId
        isInitialized = true
        print("📝 [NotionSchema] Databases configured - Content: \(contentId), Todo: \(todoId)")
    }
    
    /// Clear all schema state
    func clear() {
        rootPageId = nil
        rootPageTitle = nil
        contentDbId = nil
        todoDbId = nil
        isInitialized = false
        print("📝 [NotionSchema] Schema state cleared")
    }
    
    /// Validate current state
    func validate() -> Bool {
        guard isComplete else {
            print("⚠️ [NotionSchema] Incomplete schema state")
            return false
        }
        return true
    }
}

// MARK: - Codable Support for Export/Import

extension NotionSchemaState {
    
    struct SchemaSnapshot: Codable {
        let rootPageId: String?
        let rootPageTitle: String?
        let contentDbId: String?
        let todoDbId: String?
        let isInitialized: Bool
    }
    
    /// Export current state
    func export() -> SchemaSnapshot {
        SchemaSnapshot(
            rootPageId: rootPageId,
            rootPageTitle: rootPageTitle,
            contentDbId: contentDbId,
            todoDbId: todoDbId,
            isInitialized: isInitialized
        )
    }
    
    /// Import state from snapshot
    func importSnapshot(_ snapshot: SchemaSnapshot) {
        rootPageId = snapshot.rootPageId
        rootPageTitle = snapshot.rootPageTitle
        contentDbId = snapshot.contentDbId
        todoDbId = snapshot.todoDbId
        isInitialized = snapshot.isInitialized
    }
}
