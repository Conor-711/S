import Foundation
import AuthenticationServices
import AppKit

// MARK: - Notion OAuth Service
// Handles browser-based OAuth authentication for Notion MCP

@MainActor
final class NotionOAuthService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NotionOAuthService()
    
    // MARK: - Constants
    
    private static let mcpAuthURL = URL(string: "https://mcp.notion.com/mcp")!
    private static let callbackScheme = "s-navigator"  // Custom URL scheme for callback
    
    // MARK: - Published State
    
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?
    
    // MARK: - Properties
    
    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?
    private var oauthURL: URL?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    /// Set OAuth URL from MCP 401 response
    func setOAuthURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            self.oauthURL = url
            print("🔐 [NotionOAuth] OAuth URL set: \(urlString)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Start OAuth flow in browser
    /// Notion MCP will redirect back with session token
    func startOAuthFlow() async -> Bool {
        print("🔐 [NotionOAuth] Starting OAuth flow...")
        
        isAuthenticating = true
        authError = nil
        
        // Use OAuth URL from 401 response if available, otherwise use default
        let authURL = oauthURL ?? Self.mcpAuthURL
        print("🔐 [NotionOAuth] Using auth URL: \(authURL)")
        
        return await withCheckedContinuation { continuation in
            // Create authentication session
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    self.isAuthenticating = false
                    
                    if let error = error {
                        if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            print("🔐 [NotionOAuth] User cancelled login")
                            self.authError = "用户取消了登录"
                        } else {
                            print("🔐 [NotionOAuth] Auth error: \(error)")
                            self.authError = error.localizedDescription
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        print("🔐 [NotionOAuth] No callback URL received")
                        self.authError = "未收到授权回调"
                        continuation.resume(returning: false)
                        return
                    }
                    
                    print("🔐 [NotionOAuth] Callback received: \(callbackURL)")
                    
                    // Parse the callback URL for session token
                    if self.handleCallback(callbackURL) {
                        print("✅ [NotionOAuth] Authentication successful")
                        continuation.resume(returning: true)
                    } else {
                        self.authError = "无法解析授权信息"
                        continuation.resume(returning: false)
                    }
                }
            }
            
            // Configure session
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            self.authSession = session
            
            // Start the session
            if !session.start() {
                print("❌ [NotionOAuth] Failed to start auth session")
                self.isAuthenticating = false
                self.authError = "无法启动浏览器授权"
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Alternative: Open Notion OAuth in default browser (for systems without ASWebAuthenticationSession support)
    func openOAuthInBrowser() {
        print("🔐 [NotionOAuth] Opening OAuth in browser...")
        NSWorkspace.shared.open(Self.mcpAuthURL)
    }
    
    /// Handle OAuth callback URL
    private func handleCallback(_ url: URL) -> Bool {
        // Parse URL components
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        
        // Look for session token in query parameters or fragment
        let queryItems = components.queryItems ?? []
        
        // Check for session_id or token parameter
        if let sessionId = queryItems.first(where: { $0.name == "session_id" })?.value {
            MCPSettings.shared.setNotionToken(sessionId)
            return true
        }
        
        if let token = queryItems.first(where: { $0.name == "token" })?.value {
            MCPSettings.shared.setNotionToken(token)
            return true
        }
        
        if let accessToken = queryItems.first(where: { $0.name == "access_token" })?.value {
            MCPSettings.shared.setNotionToken(accessToken)
            return true
        }
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            authError = error
            return false
        }
        
        // If we got a callback but no token, the OAuth might have succeeded
        // and we need to try connecting again
        MCPSettings.shared.isNotionConnected = true
        return true
    }
    
    /// Cancel ongoing authentication
    func cancelAuth() {
        authSession?.cancel()
        authSession = nil
        isAuthenticating = false
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension NotionOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the main window as the presentation anchor
        if let anchor = presentationAnchor {
            return anchor
        }
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
    
    /// Set the presentation anchor window
    func setPresentationAnchor(_ window: NSWindow?) {
        self.presentationAnchor = window
    }
}

// MARK: - URL Scheme Handler

extension NotionOAuthService {
    
    /// Handle incoming URL (called from AppDelegate when app receives URL)
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme else {
            return false
        }
        
        print("🔐 [NotionOAuth] Received incoming URL: \(url)")
        
        // The ASWebAuthenticationSession should handle this automatically
        // This is a fallback for manual URL handling
        return true
    }
}
