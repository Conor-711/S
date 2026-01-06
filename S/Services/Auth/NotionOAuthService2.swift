import Foundation
import AuthenticationServices
import AppKit

// MARK: - Notion OAuth Service (Public Integration)
// Handles Notion OAuth 2.0 authentication for public integrations

@MainActor
final class NotionOAuth2Service: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NotionOAuth2Service()
    
    // MARK: - Published State
    
    @Published var isAuthenticated: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?
    @Published var workspaceName: String?
    @Published var workspaceIcon: String?
    
    // MARK: - Properties
    
    private var authSession: ASWebAuthenticationSession?
    private var accessToken: String?
    private var botId: String?
    private var workspaceId: String?
    private var duplicatedTemplateId: String?
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let accessToken = "notion.oauth.accessToken"
        static let botId = "notion.oauth.botId"
        static let workspaceId = "notion.oauth.workspaceId"
        static let workspaceName = "notion.oauth.workspaceName"
        static let workspaceIcon = "notion.oauth.workspaceIcon"
        static let duplicatedTemplateId = "notion.oauth.duplicatedTemplateId"
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        loadStoredSession()
    }
    
    // MARK: - Public Methods
    
    /// Start Notion OAuth flow
    func startOAuthFlow() async -> Bool {
        print("🔐 [NotionOAuth2] Starting OAuth flow...")
        
        isAuthenticating = true
        authError = nil
        
        // Build OAuth URL
        guard let authURL = buildAuthorizationURL() else {
            authError = "无法构建授权 URL"
            isAuthenticating = false
            return false
        }
        
        print("🔐 [NotionOAuth2] Auth URL: \(authURL)")
        
        return await withCheckedContinuation { continuation in
            // Use the app's custom URL scheme to receive the callback
            // Supabase Edge Function will redirect from https:// to s-navigator://
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: NotionOAuthConfig.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    self.isAuthenticating = false
                    
                    if let error = error {
                        if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            print("🔐 [NotionOAuth2] User cancelled login")
                            self.authError = "用户取消了登录"
                        } else {
                            print("🔐 [NotionOAuth2] Auth error: \(error)")
                            self.authError = error.localizedDescription
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        print("🔐 [NotionOAuth2] No callback URL received")
                        self.authError = "未收到授权回调"
                        continuation.resume(returning: false)
                        return
                    }
                    
                    print("🔐 [NotionOAuth2] Callback received: \(callbackURL)")
                    
                    // Extract authorization code and exchange for token
                    if await self.handleCallback(callbackURL) {
                        print("✅ [NotionOAuth2] Notion authentication successful")
                        continuation.resume(returning: true)
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            self.authSession = session
            
            if !session.start() {
                print("❌ [NotionOAuth2] Failed to start auth session")
                self.isAuthenticating = false
                self.authError = "无法启动浏览器授权"
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Disconnect Notion
    func disconnect() {
        print("🔐 [NotionOAuth2] Disconnecting...")
        
        accessToken = nil
        botId = nil
        workspaceId = nil
        workspaceName = nil
        workspaceIcon = nil
        duplicatedTemplateId = nil
        isAuthenticated = false
        
        // Clear stored session
        UserDefaults.standard.removeObject(forKey: Keys.accessToken)
        UserDefaults.standard.removeObject(forKey: Keys.botId)
        UserDefaults.standard.removeObject(forKey: Keys.workspaceId)
        UserDefaults.standard.removeObject(forKey: Keys.workspaceName)
        UserDefaults.standard.removeObject(forKey: Keys.workspaceIcon)
        UserDefaults.standard.removeObject(forKey: Keys.duplicatedTemplateId)
        
        // Also clear MCP settings and ETL schema
        MCPSettings.shared.clearNotionSettings()
        NotionSchemaState.shared.clear()
        
        print("✅ [NotionOAuth2] Disconnected successfully")
    }
    
    /// Get current access token
    func getAccessToken() -> String? {
        return accessToken
    }
    
    // MARK: - Private Methods
    
    private func buildAuthorizationURL() -> URL? {
        var components = URLComponents(string: NotionOAuthConfig.authorizationURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: NotionOAuthConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: NotionOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user")
        ]
        return components?.url
    }
    
    private func handleCallback(_ url: URL) async -> Bool {
        // Parse authorization code from callback URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            authError = "无法解析回调 URL"
            return false
        }
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            authError = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            print("❌ [NotionOAuth2] OAuth error: \(authError ?? "Unknown")")
            return false
        }
        
        // Get authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            authError = "未收到授权码"
            return false
        }
        
        print("🔐 [NotionOAuth2] Got authorization code, exchanging for token...")
        
        // Exchange code for access token
        return await exchangeCodeForToken(code)
    }
    
    private func exchangeCodeForToken(_ code: String) async -> Bool {
        guard let url = URL(string: NotionOAuthConfig.tokenURL) else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Basic auth with client_id:client_secret
        let credentials = "\(NotionOAuthConfig.clientId):\(NotionOAuthConfig.clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": NotionOAuthConfig.redirectURI
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "无效的响应"
                return false
            }
            
            print("🔐 [NotionOAuth2] Token response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? String {
                    authError = errorJson["error_description"] as? String ?? error
                } else {
                    authError = "Token 交换失败 (HTTP \(httpResponse.statusCode))"
                }
                print("❌ [NotionOAuth2] Token error: \(authError ?? "Unknown")")
                return false
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                authError = "无法解析 token 响应"
                return false
            }
            
            self.accessToken = accessToken
            self.botId = json["bot_id"] as? String
            
            // Extract workspace info
            if let workspace = json["workspace_id"] as? String {
                self.workspaceId = workspace
            }
            if let workspaceName = json["workspace_name"] as? String {
                self.workspaceName = workspaceName
            }
            if let workspaceIcon = json["workspace_icon"] as? String {
                self.workspaceIcon = workspaceIcon
            }
            
            // Extract duplicated template ID (if user chose "Use a template")
            if let templateId = json["duplicated_template_id"] as? String {
                self.duplicatedTemplateId = templateId
                print("📋 [NotionOAuth2] User chose template, duplicated page ID: \(templateId)")
            }
            
            // Store tokens
            UserDefaults.standard.set(accessToken, forKey: Keys.accessToken)
            if let botId = self.botId {
                UserDefaults.standard.set(botId, forKey: Keys.botId)
            }
            if let workspaceId = self.workspaceId {
                UserDefaults.standard.set(workspaceId, forKey: Keys.workspaceId)
            }
            if let workspaceName = self.workspaceName {
                UserDefaults.standard.set(workspaceName, forKey: Keys.workspaceName)
            }
            if let workspaceIcon = self.workspaceIcon {
                UserDefaults.standard.set(workspaceIcon, forKey: Keys.workspaceIcon)
            }
            if let templateId = self.duplicatedTemplateId {
                UserDefaults.standard.set(templateId, forKey: Keys.duplicatedTemplateId)
            }
            
            // Update MCP settings
            MCPSettings.shared.setNotionToken(accessToken)
            
            isAuthenticated = true
            print("✅ [NotionOAuth2] Token obtained successfully")
            print("   Workspace: \(self.workspaceName ?? "Unknown")")
            
            // If template was used, setup ETL schema automatically
            if let templateId = self.duplicatedTemplateId {
                await setupETLSchemaFromTemplate(templatePageId: templateId)
            }
            
            return true
            
        } catch {
            print("❌ [NotionOAuth2] Token exchange error: \(error)")
            authError = error.localizedDescription
            return false
        }
    }
    
    private func loadStoredSession() {
        guard let accessToken = UserDefaults.standard.string(forKey: Keys.accessToken) else {
            return
        }
        
        self.accessToken = accessToken
        self.botId = UserDefaults.standard.string(forKey: Keys.botId)
        self.workspaceId = UserDefaults.standard.string(forKey: Keys.workspaceId)
        self.workspaceName = UserDefaults.standard.string(forKey: Keys.workspaceName)
        self.workspaceIcon = UserDefaults.standard.string(forKey: Keys.workspaceIcon)
        self.duplicatedTemplateId = UserDefaults.standard.string(forKey: Keys.duplicatedTemplateId)
        
        isAuthenticated = true
        
        // Also update MCP settings
        MCPSettings.shared.setNotionToken(accessToken)
        
        print("✅ [NotionOAuth2] Restored session for workspace: \(workspaceName ?? "Unknown")")
    }
    
    // MARK: - ETL Schema Setup from Template
    
    /// Setup ETL schema from duplicated template page
    /// Searches for databases within the template page, creates them if not found
    private func setupETLSchemaFromTemplate(templatePageId: String) async {
        print("🔧 [NotionOAuth2] Setting up ETL schema from template page: \(templatePageId)")
        
        do {
            // Search for databases within the template page
            let databases = try await findDatabasesInPage(pageId: templatePageId)
            
            var contentDbId: String?
            var todoDbId: String?
            
            for db in databases {
                let title = db.title.lowercased()
                if title.contains("knowledge") || title.contains("content") {
                    contentDbId = db.id
                    print("   📚 Found Content DB: \(db.title) (\(db.id))")
                } else if title.contains("task") || title.contains("todo") || title.contains("to-do") {
                    todoDbId = db.id
                    print("   ✅ Found Todo DB: \(db.title) (\(db.id))")
                }
            }
            
            // If databases not found, create them
            if contentDbId == nil || todoDbId == nil {
                print("🔧 [NotionOAuth2] Databases not found in template, creating them...")
                
                let notionAPI = NotionAPIClient.shared
                
                if contentDbId == nil {
                    contentDbId = try await notionAPI.createContentDatabase(parentPageId: templatePageId)
                    print("   📚 Created Content DB: \(contentDbId!)")
                }
                
                if todoDbId == nil {
                    todoDbId = try await notionAPI.createTodoDatabase(parentPageId: templatePageId)
                    print("   ✅ Created Todo DB: \(todoDbId!)")
                }
            }
            
            // Store in NotionSchemaState
            let schemaState = NotionSchemaState.shared
            schemaState.setRootPage(id: templatePageId, title: "S")
            
            if let contentId = contentDbId, let todoId = todoDbId {
                schemaState.setDatabases(contentId: contentId, todoId: todoId)
                print("✅ [NotionOAuth2] ETL schema configured successfully")
            } else {
                print("❌ [NotionOAuth2] Failed to setup databases")
            }
            
        } catch {
            print("❌ [NotionOAuth2] Failed to setup ETL schema from template: \(error)")
        }
    }
    
    /// Find databases using blocks API first (for inline databases), then search API as fallback
    private func findDatabasesInPage(pageId: String) async throws -> [NotionDatabaseInfo] {
        guard let token = accessToken else {
            throw NotionAPIError.notAuthenticated
        }
        
        print("🔍 [NotionOAuth2] Searching for databases with parent page: \(pageId)")
        
        var databases: [NotionDatabaseInfo] = []
        
        // Add small delay to allow Notion to index the duplicated template
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        // First try blocks API to find inline databases (child_database)
        if let blocksUrl = URL(string: "\(NotionOAuthConfig.apiBaseURL)/blocks/\(pageId)/children") {
            var blocksRequest = URLRequest(url: blocksUrl)
            blocksRequest.httpMethod = "GET"
            blocksRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            blocksRequest.setValue(NotionOAuthConfig.apiVersion, forHTTPHeaderField: "Notion-Version")
            
            if let (blocksData, blocksResponse) = try? await URLSession.shared.data(for: blocksRequest),
               let blocksHttpResponse = blocksResponse as? HTTPURLResponse,
               blocksHttpResponse.statusCode == 200,
               let blocksJson = try? JSONSerialization.jsonObject(with: blocksData) as? [String: Any],
               let blocksResults = blocksJson["results"] as? [[String: Any]] {
                
                print("🔍 [NotionOAuth2] Blocks API response: \(blocksResults.count) blocks found")
                
                for block in blocksResults {
                    guard let blockType = block["type"] as? String else { continue }
                    
                    if blockType == "child_database" {
                        if let dbId = block["id"] as? String,
                           let dbInfo = block["child_database"] as? [String: Any],
                           let title = dbInfo["title"] as? String {
                            databases.append(NotionDatabaseInfo(id: dbId, title: title, icon: nil))
                            print("   📊 Found inline database: \(title) (\(dbId))")
                        }
                    }
                }
            } else {
                print("🔍 [NotionOAuth2] Blocks API failed or returned no results, trying search API...")
            }
        }
        
        // If no inline databases found, try search API
        if databases.isEmpty {
            // Use search API to find all databases the integration has access to
            guard let searchUrl = URL(string: "\(NotionOAuthConfig.apiBaseURL)/search") else {
                throw NotionAPIError.invalidURL
            }
            
            var searchRequest = URLRequest(url: searchUrl)
            searchRequest.httpMethod = "POST"
            searchRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            searchRequest.setValue(NotionOAuthConfig.apiVersion, forHTTPHeaderField: "Notion-Version")
            searchRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let searchBody: [String: Any] = [
                "filter": ["value": "database", "property": "object"],
                "page_size": 20
            ]
            searchRequest.httpBody = try? JSONSerialization.data(withJSONObject: searchBody)
            
            let (searchData, searchResponse) = try await URLSession.shared.data(for: searchRequest)
            
            guard let searchHttpResponse = searchResponse as? HTTPURLResponse else {
                throw NotionAPIError.invalidResponse
            }
            
            print("🔍 [NotionOAuth2] Search API response status: \(searchHttpResponse.statusCode)")
            
            if searchHttpResponse.statusCode == 200,
               let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
               let searchResults = searchJson["results"] as? [[String: Any]] {
                
                let normalizedTemplateId = pageId.replacingOccurrences(of: "-", with: "")
                print("🔍 [NotionOAuth2] Total databases found in search: \(searchResults.count)")
                
                // First pass: try to match by parent page ID
                for db in searchResults {
                    guard let dbId = db["id"] as? String else { continue }
                    
                    // Extract title
                    var title = "Untitled"
                    if let titleArray = db["title"] as? [[String: Any]],
                       let firstTitle = titleArray.first,
                       let plainText = firstTitle["plain_text"] as? String {
                        title = plainText
                    }
                    
                    // Check parent
                    if let parent = db["parent"] as? [String: Any] {
                        let parentId = parent["page_id"] as? String ?? parent["block_id"] as? String ?? ""
                        let normalizedParentId = parentId.replacingOccurrences(of: "-", with: "")
                        print("   📊 Database: \(title), parent: \(parentId)")
                        
                        // Match by parent page ID
                        if normalizedParentId == normalizedTemplateId {
                            databases.append(NotionDatabaseInfo(id: dbId, title: title, icon: nil))
                            print("   ✅ Matched by parent: \(title) (\(dbId))")
                        }
                    }
                }
                
                // If no databases found by parent matching, try by name pattern
                if databases.isEmpty {
                    print("🔍 [NotionOAuth2] No databases matched by parent, trying name pattern...")
                    for db in searchResults {
                        guard let dbId = db["id"] as? String else { continue }
                        
                        var title = "Untitled"
                        if let titleArray = db["title"] as? [[String: Any]],
                           let firstTitle = titleArray.first,
                           let plainText = firstTitle["plain_text"] as? String {
                            title = plainText
                        }
                        
                        let lowerTitle = title.lowercased()
                        // Match by expected database names
                        if lowerTitle.contains("knowledge") || lowerTitle.contains("content") ||
                           lowerTitle.contains("task") || lowerTitle.contains("todo") ||
                           lowerTitle.contains("visual") || lowerTitle == "to-do list" {
                            databases.append(NotionDatabaseInfo(id: dbId, title: title, icon: nil))
                            print("   ✅ Matched by name: \(title) (\(dbId))")
                        }
                    }
                }
            } else {
                let errorBody = String(data: searchData, encoding: .utf8) ?? "Unknown"
                print("❌ [NotionOAuth2] Search API error: \(errorBody)")
            }
        }
        
        print("🔍 [NotionOAuth2] Found \(databases.count) databases in template page")
        return databases
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension NotionOAuth2Service: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
