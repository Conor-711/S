import Foundation
import AuthenticationServices
import AppKit

// MARK: - Slack OAuth Service
// Handles Slack OAuth 2.0 authentication for app distribution
// V1.2: Slack integration for work-related todos

@MainActor
final class SlackOAuthService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SlackOAuthService()
    
    // MARK: - Published State
    
    @Published var isAuthenticated: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?
    @Published var teamName: String?
    @Published var channelName: String?
    
    // MARK: - Properties
    
    private var authSession: ASWebAuthenticationSession?
    private var accessToken: String?
    private var teamId: String?
    private var botUserId: String?
    private var webhookUrl: String?
    private var webhookChannelId: String?
    
    // MARK: - Configuration
    
    private enum Config {
        static let clientId = "3484211601798.10235979120821"
        // OAuth URLs
        static let authorizationURL = "https://slack.com/oauth/v2/authorize"
        // Supabase Edge Function handles callback and token exchange
        static let redirectURI = "\(SupabaseConfig.projectURL)/functions/v1/slack-oauth-callback"
        static let callbackScheme = "s-navigator"
        // Scopes needed for posting messages and accessing channels
        static let scopes = "incoming-webhook,chat:write,channels:read"
    }
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let accessToken = "slack.oauth.accessToken"
        static let teamId = "slack.oauth.teamId"
        static let teamName = "slack.oauth.teamName"
        static let botUserId = "slack.oauth.botUserId"
        static let webhookUrl = "slack.oauth.webhookUrl"
        static let webhookChannelId = "slack.oauth.webhookChannelId"
        static let channelName = "slack.oauth.channelName"
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        loadStoredSession()
    }
    
    // MARK: - Public Methods
    
    /// Start Slack OAuth flow
    func startOAuthFlow() async -> Bool {
        print("🔐 [SlackOAuth] Starting OAuth flow...")
        
        isAuthenticating = true
        authError = nil
        
        // Build OAuth URL
        guard let authURL = buildAuthorizationURL() else {
            authError = "无法构建授权 URL"
            isAuthenticating = false
            return false
        }
        
        print("🔐 [SlackOAuth] Auth URL: \(authURL)")
        
        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Config.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    self.isAuthenticating = false
                    
                    if let error = error {
                        if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            print("🔐 [SlackOAuth] User cancelled login")
                            self.authError = "用户取消了登录"
                        } else {
                            print("🔐 [SlackOAuth] Auth error: \(error)")
                            self.authError = error.localizedDescription
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        print("🔐 [SlackOAuth] No callback URL received")
                        self.authError = "未收到授权回调"
                        continuation.resume(returning: false)
                        return
                    }
                    
                    print("🔐 [SlackOAuth] Callback received: \(callbackURL)")
                    
                    // Handle callback (token already exchanged by Edge Function)
                    if self.handleCallback(callbackURL) {
                        print("✅ [SlackOAuth] Slack authentication successful")
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
                print("❌ [SlackOAuth] Failed to start auth session")
                self.isAuthenticating = false
                self.authError = "无法启动浏览器授权"
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Disconnect Slack
    func disconnect() {
        print("🔐 [SlackOAuth] Disconnecting...")
        
        accessToken = nil
        teamId = nil
        teamName = nil
        botUserId = nil
        webhookUrl = nil
        webhookChannelId = nil
        channelName = nil
        isAuthenticated = false
        
        // Clear stored session
        UserDefaults.standard.removeObject(forKey: Keys.accessToken)
        UserDefaults.standard.removeObject(forKey: Keys.teamId)
        UserDefaults.standard.removeObject(forKey: Keys.teamName)
        UserDefaults.standard.removeObject(forKey: Keys.botUserId)
        UserDefaults.standard.removeObject(forKey: Keys.webhookUrl)
        UserDefaults.standard.removeObject(forKey: Keys.webhookChannelId)
        UserDefaults.standard.removeObject(forKey: Keys.channelName)
        
        print("✅ [SlackOAuth] Disconnected successfully")
    }
    
    /// Get current access token
    func getAccessToken() -> String? {
        return accessToken
    }
    
    /// Get webhook URL for posting messages
    func getWebhookUrl() -> String? {
        return webhookUrl
    }
    
    // MARK: - Message Posting
    
    /// Post a message to the configured Slack channel
    /// - Parameters:
    ///   - text: Plain text message
    ///   - blocks: Optional Block Kit blocks for rich formatting
    /// - Returns: True if message was sent successfully
    func postMessage(text: String, blocks: [[String: Any]]? = nil) async -> Bool {
        guard let webhookUrl = webhookUrl, let url = URL(string: webhookUrl) else {
            print("❌ [SlackOAuth] No webhook URL configured")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["text": text]
        if let blocks = blocks {
            body["blocks"] = blocks
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [SlackOAuth] Invalid response")
                return false
            }
            
            if httpResponse.statusCode == 200 {
                print("✅ [SlackOAuth] Message posted successfully")
                return true
            } else {
                print("❌ [SlackOAuth] Failed to post message: HTTP \(httpResponse.statusCode)")
                return false
            }
        } catch {
            print("❌ [SlackOAuth] Error posting message: \(error)")
            return false
        }
    }
    
    /// Post a work todo to Slack with rich formatting
    func postWorkTodo(title: String, description: String?, assignee: String?, dueDate: String?, userNote: String?) async -> Bool {
        // Build Block Kit message
        var blocks: [[String: Any]] = [
            [
                "type": "header",
                "text": [
                    "type": "plain_text",
                    "text": "📋 新工作任务",
                    "emoji": true
                ]
            ],
            [
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*\(title)*"
                ]
            ]
        ]
        
        // Add description if present
        if let desc = description, !desc.isEmpty {
            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": desc
                ]
            ])
        }
        
        // Add metadata fields
        var fields: [[String: Any]] = []
        
        if let assignee = assignee, !assignee.isEmpty {
            fields.append([
                "type": "mrkdwn",
                "text": "*负责人:*\n\(assignee)"
            ])
        }
        
        if let dueDate = dueDate, !dueDate.isEmpty {
            fields.append([
                "type": "mrkdwn",
                "text": "*截止日期:*\n\(dueDate)"
            ])
        }
        
        if !fields.isEmpty {
            blocks.append([
                "type": "section",
                "fields": fields
            ])
        }
        
        // Add user note if present
        if let note = userNote, !note.isEmpty {
            blocks.append([
                "type": "context",
                "elements": [
                    [
                        "type": "mrkdwn",
                        "text": "💭 _\(note)_"
                    ]
                ]
            ])
        }
        
        // Add divider
        blocks.append(["type": "divider"])
        
        // Plain text fallback
        let plainText = "📋 新工作任务: \(title)"
        
        return await postMessage(text: plainText, blocks: blocks)
    }
    
    // MARK: - Private Methods
    
    private func buildAuthorizationURL() -> URL? {
        var components = URLComponents(string: Config.authorizationURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "scope", value: Config.scopes),
            URLQueryItem(name: "response_type", value: "code")
        ]
        return components?.url
    }
    
    private func handleCallback(_ url: URL) -> Bool {
        // Parse tokens from callback URL (already exchanged by Edge Function)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            authError = "无法解析回调 URL"
            return false
        }
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            authError = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            print("❌ [SlackOAuth] OAuth error: \(authError ?? "Unknown")")
            return false
        }
        
        // Get access token (exchanged by Edge Function)
        guard let token = queryItems.first(where: { $0.name == "access_token" })?.value else {
            authError = "未收到访问令牌"
            return false
        }
        
        self.accessToken = token
        self.teamId = queryItems.first(where: { $0.name == "team_id" })?.value
        self.teamName = queryItems.first(where: { $0.name == "team_name" })?.value
        self.botUserId = queryItems.first(where: { $0.name == "bot_user_id" })?.value
        self.webhookUrl = queryItems.first(where: { $0.name == "webhook_url" })?.value
        self.webhookChannelId = queryItems.first(where: { $0.name == "webhook_channel_id" })?.value
        self.channelName = queryItems.first(where: { $0.name == "webhook_channel" })?.value
        
        // Store tokens
        UserDefaults.standard.set(token, forKey: Keys.accessToken)
        if let teamId = self.teamId {
            UserDefaults.standard.set(teamId, forKey: Keys.teamId)
        }
        if let teamName = self.teamName {
            UserDefaults.standard.set(teamName, forKey: Keys.teamName)
        }
        if let botUserId = self.botUserId {
            UserDefaults.standard.set(botUserId, forKey: Keys.botUserId)
        }
        if let webhookUrl = self.webhookUrl {
            UserDefaults.standard.set(webhookUrl, forKey: Keys.webhookUrl)
        }
        if let webhookChannelId = self.webhookChannelId {
            UserDefaults.standard.set(webhookChannelId, forKey: Keys.webhookChannelId)
        }
        if let channelName = self.channelName {
            UserDefaults.standard.set(channelName, forKey: Keys.channelName)
        }
        
        isAuthenticated = true
        print("✅ [SlackOAuth] Token stored successfully")
        print("   Team: \(self.teamName ?? "Unknown")")
        print("   Channel: \(self.channelName ?? "Unknown")")
        
        return true
    }
    
    private func loadStoredSession() {
        guard let accessToken = UserDefaults.standard.string(forKey: Keys.accessToken) else {
            return
        }
        
        self.accessToken = accessToken
        self.teamId = UserDefaults.standard.string(forKey: Keys.teamId)
        self.teamName = UserDefaults.standard.string(forKey: Keys.teamName)
        self.botUserId = UserDefaults.standard.string(forKey: Keys.botUserId)
        self.webhookUrl = UserDefaults.standard.string(forKey: Keys.webhookUrl)
        self.webhookChannelId = UserDefaults.standard.string(forKey: Keys.webhookChannelId)
        self.channelName = UserDefaults.standard.string(forKey: Keys.channelName)
        
        isAuthenticated = true
        
        print("✅ [SlackOAuth] Restored session for team: \(teamName ?? "Unknown"), channel: \(channelName ?? "Unknown")")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SlackOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
