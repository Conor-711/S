import Foundation

// MARK: - Notion API Client
// Direct Notion API client using OAuth access token
// This replaces MCP for direct API operations

@MainActor
final class NotionAPIClient: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NotionAPIClient()
    
    // MARK: - Constants
    
    private static let apiBaseURL = "https://api.notion.com/v1"
    private static let apiVersion = "2022-06-28"
    
    // MARK: - Properties
    
    @Published var isConnected: Bool = false
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Connection
    
    func connect() async -> Bool {
        guard let token = NotionOAuth2Service.shared.getAccessToken() else {
            print("❌ [NotionAPI] No access token available")
            return false
        }
        
        // Test connection by fetching user info
        do {
            let _ = try await getMe()
            isConnected = true
            print("✅ [NotionAPI] Connected successfully")
            return true
        } catch {
            print("❌ [NotionAPI] Connection failed: \(error)")
            isConnected = false
            return false
        }
    }
    
    func disconnect() {
        isConnected = false
    }
    
    // MARK: - User Info
    
    func getMe() async throws -> [String: Any] {
        return try await request(endpoint: "/users/me", method: "GET")
    }
    
    // MARK: - Search
    
    func search(query: String, filter: SearchFilter? = nil) async throws -> NotionSearchResult {
        var body: [String: Any] = ["query": query]
        
        if let filter = filter {
            body["filter"] = ["property": "object", "value": filter.rawValue]
        }
        
        let response = try await request(endpoint: "/search", method: "POST", body: body)
        return try parseSearchResult(response)
    }
    
    enum SearchFilter: String {
        case page
        case database
    }
    
    // MARK: - Pages
    
    func createPage(parentId: String, parentType: ParentType, title: String, content: String? = nil) async throws -> String {
        var parent: [String: Any]
        switch parentType {
        case .page:
            parent = ["page_id": parentId]
        case .database:
            parent = ["database_id": parentId]
        }
        
        var properties: [String: Any] = [:]
        
        if parentType == .database {
            // For database entries, use "Name" or "title" property
            properties["Name"] = [
                "title": [
                    ["type": "text", "text": ["content": title]]
                ]
            ]
        }
        
        var body: [String: Any] = [
            "parent": parent,
            "properties": properties
        ]
        
        // Add title as page title for page parents
        if parentType == .page {
            body["properties"] = [
                "title": [
                    ["type": "text", "text": ["content": title]]
                ]
            ]
        }
        
        // Add content as children blocks
        if let content = content, !content.isEmpty {
            let paragraphs = content.components(separatedBy: "\n\n")
            var children: [[String: Any]] = []
            
            for paragraph in paragraphs {
                if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    children.append([
                        "object": "block",
                        "type": "paragraph",
                        "paragraph": [
                            "rich_text": [
                                ["type": "text", "text": ["content": paragraph]]
                            ]
                        ]
                    ])
                }
            }
            
            body["children"] = children
        }
        
        let response = try await request(endpoint: "/pages", method: "POST", body: body)
        
        guard let pageId = response["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        
        print("✅ [NotionAPI] Created page: \(pageId)")
        return pageId
    }
    
    enum ParentType {
        case page
        case database
    }
    
    // MARK: - Append to Page
    
    func appendToPage(pageId: String, content: String) async throws {
        let paragraphs = content.components(separatedBy: "\n\n")
        var children: [[String: Any]] = []
        
        for paragraph in paragraphs {
            if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                children.append([
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [
                            ["type": "text", "text": ["content": paragraph]]
                        ]
                    ]
                ])
            }
        }
        
        let body: [String: Any] = ["children": children]
        
        let _ = try await request(endpoint: "/blocks/\(pageId)/children", method: "PATCH", body: body)
        print("✅ [NotionAPI] Appended content to page: \(pageId)")
    }
    
    // MARK: - Database Entry
    
    func createDatabaseEntry(databaseId: String, properties: [String: Any]) async throws -> String {
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties
        ]
        
        let response = try await request(endpoint: "/pages", method: "POST", body: body)
        
        guard let pageId = response["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        
        print("✅ [NotionAPI] Created database entry: \(pageId)")
        return pageId
    }
    
    // MARK: - V1.1 Create Page and Database
    
    /// Create a new "S" page at workspace root level for Visual ETL
    /// For Public Integrations: uses parent: { workspace: true } to create at workspace level
    /// This creates a private page owned by the authorizing user
    func createETLRootPage(title: String = "S") async throws -> String {
        print("🔧 [NotionAPI] Creating page at workspace root level...")
        
        // For Public Integrations, we can create pages at workspace level
        // by setting parent: { workspace: true }
        // This creates a private page for the user who authorized the integration
        let body: [String: Any] = [
            "parent": ["workspace": true],
            "icon": ["type": "emoji", "emoji": "📸"],
            "properties": [
                "title": [
                    ["type": "text", "text": ["content": title]]
                ]
            ]
        ]
        
        let response = try await request(endpoint: "/pages", method: "POST", body: body)
        
        guard let pageId = response["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        
        print("✅ [NotionAPI] Created ETL Root Page '\(title)' at workspace level: \(pageId)")
        return pageId
    }
    
    /// Create a new "S" page inside a specific parent page for Visual ETL
    func createETLRootPage(parentPageId: String, title: String = "S") async throws -> String {
        let body: [String: Any] = [
            "parent": ["page_id": parentPageId],
            "icon": ["type": "emoji", "emoji": "📸"],
            "properties": [
                "title": [
                    ["type": "text", "text": ["content": title]]
                ]
            ]
        ]
        
        let response = try await request(endpoint: "/pages", method: "POST", body: body)
        
        guard let pageId = response["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        
        print("✅ [NotionAPI] Created ETL Root Page '\(title)' under parent: \(pageId)")
        return pageId
    }
    
    /// Create Content Database (Visual Knowledge) inside a parent page
    /// V1.2: Added Note field for user notes
    func createContentDatabase(parentPageId: String) async throws -> String {
        let body: [String: Any] = [
            "parent": ["page_id": parentPageId],
            "title": [
                ["type": "text", "text": ["content": "Visual Knowledge"]]
            ],
            "is_inline": true,
            "properties": [
                "Name": ["title": [:]],
                "Description": ["rich_text": [:]],
                "Note": ["rich_text": [:]],  // V1.2: User note (AI enhanced)
                "Category": [
                    "select": [
                        "options": [
                            ["name": "AI", "color": "blue"],
                            ["name": "Design", "color": "purple"],
                            ["name": "Product", "color": "green"]
                        ]
                    ]
                ],
                "URL": ["url": [:]],
                "Captured At": ["date": [:]]
            ]
        ]
        
        let response = try await request(endpoint: "/databases", method: "POST", body: body)
        
        guard let dbId = response["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        
        print("✅ [NotionAPI] Created Content Database: \(dbId)")
        return dbId
    }
    
    /// Create To-do Database (Visual Tasks) inside a parent page
    /// V1.2: Added Note field for user notes
    func createTodoDatabase(parentPageId: String) async throws -> String {
        let body: [String: Any] = [
            "parent": ["page_id": parentPageId],
            "title": [
                ["type": "text", "text": ["content": "Visual Tasks"]]
            ],
            "is_inline": true,
            "properties": [
                "Task": ["title": [:]],
                "Due Date": ["date": [:]],
                "Assignee": ["rich_text": [:]],
                "Status": ["checkbox": [:]],
                "Description": ["rich_text": [:]],
                "Note": ["rich_text": [:]]  // V1.2: User note (AI enhanced)
            ]
        ]
        
        let response = try await request(endpoint: "/databases", method: "POST", body: body)
        
        guard let dbId = response["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        
        print("✅ [NotionAPI] Created Todo Database: \(dbId)")
        return dbId
    }
    
    // MARK: - V1.1 Save Atom to Database
    
    /// Save Content Atom to Content Database
    /// V1.2: Added Note field support
    func saveContentAtom(_ payload: AtomPayload, toDatabaseId: String) async throws -> String {
        var properties: [String: Any] = [
            "Name": [
                "title": [
                    ["type": "text", "text": ["content": payload.title]]
                ]
            ],
            "Captured At": [
                "date": ["start": payload.capturedAt]
            ]
        ]
        
        if let description = payload.description, !description.isEmpty {
            properties["Description"] = [
                "rich_text": [
                    ["type": "text", "text": ["content": String(description.prefix(2000))]]
                ]
            ]
        }
        
        // V1.2: Add user note if present
        if let note = payload.userNote, !note.isEmpty {
            properties["Note"] = [
                "rich_text": [
                    ["type": "text", "text": ["content": String(note.prefix(2000))]]
                ]
            ]
        }
        
        if let category = payload.category {
            properties["Category"] = [
                "select": ["name": category]
            ]
        }
        
        if let url = payload.sourceUrl, !url.isEmpty {
            properties["URL"] = [
                "url": url
            ]
        }
        
        return try await createDatabaseEntry(databaseId: toDatabaseId, properties: properties)
    }
    
    /// Save Todo Atom to Todo Database
    /// V1.2: Added Note field support
    func saveTodoAtom(_ payload: AtomPayload, toDatabaseId: String) async throws -> String {
        var properties: [String: Any] = [
            "Task": [
                "title": [
                    ["type": "text", "text": ["content": payload.title]]
                ]
            ],
            "Status": [
                "checkbox": false
            ]
        ]
        
        if let description = payload.description, !description.isEmpty {
            properties["Description"] = [
                "rich_text": [
                    ["type": "text", "text": ["content": String(description.prefix(2000))]]
                ]
            ]
        }
        
        // V1.2: Add user note if present
        if let note = payload.userNote, !note.isEmpty {
            properties["Note"] = [
                "rich_text": [
                    ["type": "text", "text": ["content": String(note.prefix(2000))]]
                ]
            ]
        }
        
        if let assignee = payload.assigneeName, !assignee.isEmpty {
            properties["Assignee"] = [
                "rich_text": [
                    ["type": "text", "text": ["content": assignee]]
                ]
            ]
        }
        
        if let dueDate = payload.dueDate {
            properties["Due Date"] = [
                "date": ["start": dueDate]
            ]
        }
        
        return try await createDatabaseEntry(databaseId: toDatabaseId, properties: properties)
    }
    
    // MARK: - Save VLM Analysis Result (Legacy)
    
    func saveVLMAnalysisResult(title: String, content: String, category: String, confidence: Double) async throws -> String {
        let settings = MCPSettings.shared
        
        // Determine where to save
        if let databaseId = settings.notionTargetDatabaseId {
            // Save to database
            let properties: [String: Any] = [
                "Name": [
                    "title": [
                        ["type": "text", "text": ["content": title]]
                    ]
                ],
                "Category": [
                    "select": ["name": category]
                ],
                "Confidence": [
                    "number": confidence
                ],
                "Content": [
                    "rich_text": [
                        ["type": "text", "text": ["content": String(content.prefix(2000))]]
                    ]
                ]
            ]
            
            return try await createDatabaseEntry(databaseId: databaseId, properties: properties)
            
        } else if let pageId = settings.notionTargetPageId {
            // Save as child page
            return try await createPage(parentId: pageId, parentType: .page, title: title, content: content)
            
        } else {
            throw NotionAPIError.noTargetConfigured
        }
    }
    
    // MARK: - Private Methods
    
    private func request(endpoint: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let token = NotionOAuth2Service.shared.getAccessToken() else {
            throw NotionAPIError.notAuthenticated
        }
        
        guard let url = URL(string: "\(Self.apiBaseURL)\(endpoint)") else {
            throw NotionAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        print("📤 [NotionAPI] \(method) \(endpoint)")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidResponse
        }
        
        print("📥 [NotionAPI] Response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 401 {
            throw NotionAPIError.unauthorized
        }
        
        if httpResponse.statusCode == 403 {
            throw NotionAPIError.forbidden
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ [NotionAPI] Error: \(errorBody)")
            throw NotionAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionAPIError.invalidResponse
        }
        
        return json
    }
    
    private func parseSearchResult(_ response: [String: Any]) throws -> NotionSearchResult {
        guard let results = response["results"] as? [[String: Any]] else {
            return NotionSearchResult(pages: [], databases: [])
        }
        
        var pages: [NotionPageInfo] = []
        var databases: [NotionDatabaseInfo] = []
        
        for result in results {
            guard let objectType = result["object"] as? String,
                  let id = result["id"] as? String else {
                continue
            }
            
            if objectType == "page" {
                let title = extractTitle(from: result)
                let icon = extractIcon(from: result)
                pages.append(NotionPageInfo(id: id, title: title, icon: icon, isDatabase: false))
            } else if objectType == "database" {
                let title = extractDatabaseTitle(from: result)
                let icon = extractIcon(from: result)
                databases.append(NotionDatabaseInfo(id: id, title: title, icon: icon))
            }
        }
        
        return NotionSearchResult(pages: pages, databases: databases)
    }
    
    private func extractTitle(from page: [String: Any]) -> String {
        if let properties = page["properties"] as? [String: Any] {
            for (_, value) in properties {
                if let prop = value as? [String: Any],
                   let titleArray = prop["title"] as? [[String: Any]],
                   let firstTitle = titleArray.first,
                   let plainText = firstTitle["plain_text"] as? String {
                    return plainText
                }
            }
        }
        return "Untitled"
    }
    
    private func extractDatabaseTitle(from database: [String: Any]) -> String {
        if let titleArray = database["title"] as? [[String: Any]],
           let firstTitle = titleArray.first,
           let plainText = firstTitle["plain_text"] as? String {
            return plainText
        }
        return "Untitled Database"
    }
    
    private func extractIcon(from item: [String: Any]) -> String? {
        if let icon = item["icon"] as? [String: Any] {
            if let emoji = icon["emoji"] as? String {
                return emoji
            }
        }
        return nil
    }
}

// MARK: - Error Types

enum NotionAPIError: Error, LocalizedError {
    case notAuthenticated
    case unauthorized
    case forbidden
    case invalidURL
    case invalidResponse
    case noTargetConfigured
    case apiError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "未登录 Notion"
        case .unauthorized:
            return "Notion 授权已过期，请重新连接"
        case .forbidden:
            return "没有访问权限"
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "无效的响应"
        case .noTargetConfigured:
            return "请先设置目标页面或数据库"
        case .apiError(let statusCode, let message):
            return "API 错误 (\(statusCode)): \(message)"
        }
    }
}

// MARK: - Response Types

struct NotionSearchResult {
    let pages: [NotionPageInfo]
    let databases: [NotionDatabaseInfo]
}

struct NotionDatabaseInfo: Identifiable {
    let id: String
    let title: String
    let icon: String?
}
