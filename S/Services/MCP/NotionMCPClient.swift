import Foundation

// MARK: - Notion MCP Client
// Implements HTTP Streamable transport for Notion MCP
// Reference: https://developers.notion.com/docs/get-started-with-mcp

@MainActor
final class NotionMCPClient: MCPClientProtocol, @unchecked Sendable {
    
    // MARK: - Constants
    
    private static let mcpEndpoint = URL(string: "https://mcp.notion.com/mcp")!
    private static let sseEndpoint = URL(string: "https://mcp.notion.com/sse")!
    
    // MARK: - Properties
    
    let serverName: String = "Notion"
    
    private var sessionId: String?
    private var cachedTools: [MCPTool]?
    private var connectionState: MCPConnectionState = .disconnected
    private let urlSession: URLSession
    
    var isConnected: Bool {
        get async {
            connectionState == .connected
        }
    }
    
    // MARK: - Initialization
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - MCPClientProtocol Implementation
    
    func connect() async throws {
        print("🔗 [NotionMCP] Connecting to \(Self.mcpEndpoint)...")
        connectionState = .connecting
        
        do {
            // Initialize session with MCP server
            let initRequest = MCPJSONRPCRequest(
                method: "initialize",
                params: [
                    "protocolVersion": AnyCodable("2024-11-05"),
                    "capabilities": AnyCodable([
                        "tools": ["listChanged": true]
                    ]),
                    "clientInfo": AnyCodable([
                        "name": "S-Navigator",
                        "version": "1.0.0"
                    ])
                ]
            )
            
            let response = try await sendRequest(initRequest)
            
            if let error = response.error {
                throw ConnectorError.mcpConnectionLost(server: "Notion: \(error.message)")
            }
            
            // Extract session info if available
            if let result = response.result?.value as? [String: Any],
               let sessionId = result["sessionId"] as? String {
                self.sessionId = sessionId
            }
            
            connectionState = .connected
            print("✅ [NotionMCP] Connected successfully")
            
            // Send initialized notification
            let initializedNotification = MCPJSONRPCRequest(
                method: "notifications/initialized"
            )
            _ = try? await sendRequest(initializedNotification)
            
        } catch {
            connectionState = .error(error.localizedDescription)
            print("❌ [NotionMCP] Connection failed: \(error)")
            throw error
        }
    }
    
    func disconnect() async {
        print("🔌 [NotionMCP] Disconnecting...")
        sessionId = nil
        cachedTools = nil
        connectionState = .disconnected
    }
    
    func listTools() async throws -> [MCPTool] {
        // Return cached tools if available
        if let cached = cachedTools {
            return cached
        }
        
        print("🔧 [NotionMCP] Listing available tools...")
        
        let request = MCPJSONRPCRequest(method: "tools/list")
        let response = try await sendRequest(request)
        
        if let error = response.error {
            throw ConnectorError.mcpConnectionLost(server: "Notion: \(error.message)")
        }
        
        guard let result = response.result?.value as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            throw ConnectorError.invalidResponse
        }
        
        let tools = toolsArray.compactMap { toolDict -> MCPTool? in
            guard let name = toolDict["name"] as? String else { return nil }
            let description = toolDict["description"] as? String
            
            var inputSchema: MCPInputSchema? = nil
            if let schemaDict = toolDict["inputSchema"] as? [String: Any] {
                inputSchema = parseInputSchema(schemaDict)
            }
            
            return MCPTool(name: name, description: description, inputSchema: inputSchema)
        }
        
        cachedTools = tools
        print("🔧 [NotionMCP] Found \(tools.count) tools")
        return tools
    }
    
    func executeTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        print("⚡ [NotionMCP] Executing tool: \(name)")
        print("   Arguments: \(arguments)")
        
        // Ensure connected
        if connectionState != .connected {
            try await connect()
        }
        
        let request = MCPJSONRPCRequest(
            method: "tools/call",
            params: [
                "name": AnyCodable(name),
                "arguments": AnyCodable(arguments)
            ]
        )
        
        let response = try await sendRequest(request)
        
        if let error = response.error {
            print("❌ [NotionMCP] Tool execution failed: \(error.message)")
            return .failure(error.message)
        }
        
        // Parse result content
        if let result = response.result?.value as? [String: Any] {
            if let content = result["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                print("✅ [NotionMCP] Tool executed successfully")
                return .success(text)
            }
            
            // Fallback: serialize entire result
            if let jsonData = try? JSONSerialization.data(withJSONObject: result),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return .success(jsonString)
            }
        }
        
        return .success("Tool executed")
    }
    
    // MARK: - Notion-Specific Tool Methods
    
    /// Create a new page in Notion
    /// Uses configured target from MCPSettings if no parent specified
    func createPage(title: String, content: String, parentDatabaseId: String? = nil) async throws -> MCPToolResult {
        var args: [String: Any] = [
            "title": title,
            "markdown": content
        ]
        
        // Use provided parent, or fall back to settings
        if let databaseId = parentDatabaseId {
            args["database_id"] = databaseId
        } else {
            let settings = await MCPSettings.shared
            if let targetDbId = await settings.notionTargetDatabaseId {
                args["database_id"] = targetDbId
            } else if let targetPageId = await settings.notionTargetPageId {
                args["parent_page_id"] = targetPageId
            }
        }
        
        return try await executeTool(name: "notion_create_page", arguments: args)
    }
    
    /// Search Notion pages
    func searchPages(query: String, limit: Int = 10) async throws -> MCPToolResult {
        let args: [String: Any] = [
            "query": query,
            "page_size": limit
        ]
        
        return try await executeTool(name: "notion_search", arguments: args)
    }
    
    /// Get page content
    func getPageContent(pageId: String) async throws -> MCPToolResult {
        let args: [String: Any] = [
            "page_id": pageId
        ]
        
        return try await executeTool(name: "notion_retrieve_page", arguments: args)
    }
    
    /// Append content to existing page
    func appendToPage(pageId: String, content: String) async throws -> MCPToolResult {
        let args: [String: Any] = [
            "block_id": pageId,
            "markdown": content
        ]
        
        return try await executeTool(name: "notion_append_block_children", arguments: args)
    }
    
    /// Create database entry
    func createDatabaseEntry(databaseId: String, properties: [String: Any]) async throws -> MCPToolResult {
        var args: [String: Any] = [
            "database_id": databaseId,
            "properties": properties
        ]
        
        return try await executeTool(name: "notion_create_database_item", arguments: args)
    }
    
    // MARK: - Private Methods
    
    private func sendRequest(_ request: MCPJSONRPCRequest) async throws -> MCPJSONRPCResponse {
        var urlRequest = URLRequest(url: Self.mcpEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add session ID if available
        if let sessionId = sessionId {
            urlRequest.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        
        // Add OAuth token if available
        let settings = await MCPSettings.shared
        if let token = await settings.notionApiToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        print("📤 [NotionMCP] Sending: \(request.method)")
        
        let (data, httpResponse) = try await urlSession.data(for: urlRequest)
        
        guard let response = httpResponse as? HTTPURLResponse else {
            throw ConnectorError.invalidResponse
        }
        
        print("📥 [NotionMCP] Response status: \(response.statusCode)")
        
        // Handle OAuth redirect (401/403)
        if response.statusCode == 401 || response.statusCode == 403 {
            // Log response body for debugging
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            print("🔐 [NotionMCP] Auth response body: \(responseBody)")
            
            // Extract OAuth URL from Location header
            if let authURL = response.value(forHTTPHeaderField: "Location") {
                print("🔐 [NotionMCP] OAuth URL from header: \(authURL)")
                // Store the OAuth URL for the OAuth service to use
                await NotionOAuthService.shared.setOAuthURL(authURL)
            }
            
            // Also check WWW-Authenticate header
            if let wwwAuth = response.value(forHTTPHeaderField: "WWW-Authenticate") {
                print("🔐 [NotionMCP] WWW-Authenticate: \(wwwAuth)")
            }
            
            // Check all response headers
            print("🔐 [NotionMCP] All headers: \(response.allHeaderFields)")
            
            throw ConnectorError.authenticationRequired
        }
        
        // Check for session ID in response headers
        if let newSessionId = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            self.sessionId = newSessionId
        }
        
        guard response.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ConnectorError.mcpConnectionLost(server: "Notion (HTTP \(response.statusCode)): \(errorBody)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(MCPJSONRPCResponse.self, from: data)
    }
    
    private func parseInputSchema(_ dict: [String: Any]) -> MCPInputSchema {
        let type = dict["type"] as? String ?? "object"
        let required = dict["required"] as? [String]
        
        var properties: [String: MCPPropertySchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            properties = propsDict.mapValues { propDict in
                MCPPropertySchema(
                    type: propDict["type"] as? String ?? "string",
                    description: propDict["description"] as? String,
                    enumValues: propDict["enum"] as? [String]
                )
            }
        }
        
        return MCPInputSchema(type: type, properties: properties, required: required)
    }
}

// MARK: - Notion MCP Tool Names

extension NotionMCPClient {
    enum ToolName {
        static let createPage = "notion_create_page"
        static let search = "notion_search"
        static let retrievePage = "notion_retrieve_page"
        static let appendBlockChildren = "notion_append_block_children"
        static let createDatabaseItem = "notion_create_database_item"
        static let retrieveDatabase = "notion_retrieve_database"
        static let queryDatabase = "notion_query_database"
        static let updatePage = "notion_update_page"
        static let retrieveComments = "notion_retrieve_comments"
        static let createComment = "notion_create_comment"
    }
}
