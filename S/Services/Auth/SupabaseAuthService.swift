import Foundation
import AuthenticationServices
import AppKit

// MARK: - Supabase Auth Service
// Handles Google OAuth authentication via Supabase

@MainActor
final class SupabaseAuthService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SupabaseAuthService()
    
    // MARK: - Published State
    
    @Published var isAuthenticated: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var currentUser: SupabaseUser?
    @Published var authError: String?
    
    // MARK: - Properties
    
    private var authSession: ASWebAuthenticationSession?
    private var accessToken: String?
    private var refreshToken: String?
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let accessToken = "supabase.accessToken"
        static let refreshToken = "supabase.refreshToken"
        static let userId = "supabase.userId"
        static let userEmail = "supabase.userEmail"
        static let userName = "supabase.userName"
        static let userAvatarURL = "supabase.userAvatarURL"
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        loadStoredSession()
    }
    
    // MARK: - Public Methods
    
    /// Sign in with Google via Supabase OAuth
    func signInWithGoogle() async -> Bool {
        print("🔐 [SupabaseAuth] Starting Google OAuth flow...")
        
        isAuthenticating = true
        authError = nil
        
        // Build OAuth URL
        guard let authURL = buildGoogleOAuthURL() else {
            authError = "无法构建授权 URL"
            isAuthenticating = false
            return false
        }
        
        print("🔐 [SupabaseAuth] Auth URL: \(authURL)")
        
        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: SupabaseConfig.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    self.isAuthenticating = false
                    
                    if let error = error {
                        if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            print("🔐 [SupabaseAuth] User cancelled login")
                            self.authError = "用户取消了登录"
                        } else {
                            print("🔐 [SupabaseAuth] Auth error: \(error)")
                            self.authError = error.localizedDescription
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        print("🔐 [SupabaseAuth] No callback URL received")
                        self.authError = "未收到授权回调"
                        continuation.resume(returning: false)
                        return
                    }
                    
                    print("🔐 [SupabaseAuth] Callback received: \(callbackURL)")
                    
                    // Parse the callback URL for tokens
                    if await self.handleCallback(callbackURL) {
                        print("✅ [SupabaseAuth] Google authentication successful")
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
                print("❌ [SupabaseAuth] Failed to start auth session")
                self.isAuthenticating = false
                self.authError = "无法启动浏览器授权"
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Sign out
    func signOut() {
        print("🔐 [SupabaseAuth] Signing out...")
        
        accessToken = nil
        refreshToken = nil
        currentUser = nil
        isAuthenticated = false
        
        // Clear stored session
        UserDefaults.standard.removeObject(forKey: Keys.accessToken)
        UserDefaults.standard.removeObject(forKey: Keys.refreshToken)
        UserDefaults.standard.removeObject(forKey: Keys.userId)
        UserDefaults.standard.removeObject(forKey: Keys.userEmail)
        UserDefaults.standard.removeObject(forKey: Keys.userName)
        UserDefaults.standard.removeObject(forKey: Keys.userAvatarURL)
        
        print("✅ [SupabaseAuth] Signed out successfully")
    }
    
    /// Get current access token
    func getAccessToken() -> String? {
        return accessToken
    }
    
    /// Refresh the access token
    func refreshAccessToken() async -> Bool {
        guard let refreshToken = refreshToken else {
            print("❌ [SupabaseAuth] No refresh token available")
            return false
        }
        
        print("🔄 [SupabaseAuth] Refreshing access token...")
        
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/token?grant_type=refresh_token") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = ["refresh_token": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ [SupabaseAuth] Token refresh failed")
                return false
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccessToken = json["access_token"] as? String,
               let newRefreshToken = json["refresh_token"] as? String {
                
                self.accessToken = newAccessToken
                self.refreshToken = newRefreshToken
                
                UserDefaults.standard.set(newAccessToken, forKey: Keys.accessToken)
                UserDefaults.standard.set(newRefreshToken, forKey: Keys.refreshToken)
                
                print("✅ [SupabaseAuth] Token refreshed successfully")
                return true
            }
        } catch {
            print("❌ [SupabaseAuth] Token refresh error: \(error)")
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    private func buildGoogleOAuthURL() -> URL? {
        var components = URLComponents(string: "\(SupabaseConfig.projectURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: SupabaseConfig.googleProvider),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.callbackURL)
        ]
        return components?.url
    }
    
    private func handleCallback(_ url: URL) async -> Bool {
        // Parse URL fragment or query parameters
        // Supabase returns tokens in the URL fragment: #access_token=xxx&refresh_token=xxx
        
        var tokenString = url.fragment ?? ""
        
        // If no fragment, check query string
        if tokenString.isEmpty {
            tokenString = url.query ?? ""
        }
        
        // Parse the token string
        var params: [String: String] = [:]
        for pair in tokenString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                params[key] = value
            }
        }
        
        print("🔐 [SupabaseAuth] Parsed params: \(params.keys)")
        
        // Extract tokens
        guard let accessToken = params["access_token"] else {
            // Check for error
            if let error = params["error"] {
                authError = params["error_description"] ?? error
                print("❌ [SupabaseAuth] OAuth error: \(authError ?? "Unknown")")
            } else {
                authError = "未收到访问令牌"
            }
            return false
        }
        
        self.accessToken = accessToken
        self.refreshToken = params["refresh_token"]
        
        // Store tokens
        UserDefaults.standard.set(accessToken, forKey: Keys.accessToken)
        if let refreshToken = self.refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: Keys.refreshToken)
        }
        
        // Fetch user info
        await fetchUserInfo()
        
        isAuthenticated = true
        return true
    }
    
    private func fetchUserInfo() async {
        guard let accessToken = accessToken else { return }
        
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/user") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ [SupabaseAuth] Failed to fetch user info")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let id = json["id"] as? String ?? ""
                let email = json["email"] as? String ?? ""
                
                var name = ""
                var avatarURL: String? = nil
                
                if let userMetadata = json["user_metadata"] as? [String: Any] {
                    name = userMetadata["full_name"] as? String ?? userMetadata["name"] as? String ?? ""
                    avatarURL = userMetadata["avatar_url"] as? String ?? userMetadata["picture"] as? String
                }
                
                currentUser = SupabaseUser(
                    id: id,
                    email: email,
                    name: name,
                    avatarURL: avatarURL
                )
                
                // Store user info
                UserDefaults.standard.set(id, forKey: Keys.userId)
                UserDefaults.standard.set(email, forKey: Keys.userEmail)
                UserDefaults.standard.set(name, forKey: Keys.userName)
                if let avatarURL = avatarURL {
                    UserDefaults.standard.set(avatarURL, forKey: Keys.userAvatarURL)
                }
                
                print("✅ [SupabaseAuth] User info fetched: \(name) (\(email))")
            }
        } catch {
            print("❌ [SupabaseAuth] Error fetching user info: \(error)")
        }
    }
    
    private func loadStoredSession() {
        guard let accessToken = UserDefaults.standard.string(forKey: Keys.accessToken) else {
            return
        }
        
        self.accessToken = accessToken
        self.refreshToken = UserDefaults.standard.string(forKey: Keys.refreshToken)
        
        // Load user info
        let userId = UserDefaults.standard.string(forKey: Keys.userId) ?? ""
        let email = UserDefaults.standard.string(forKey: Keys.userEmail) ?? ""
        let name = UserDefaults.standard.string(forKey: Keys.userName) ?? ""
        let avatarURL = UserDefaults.standard.string(forKey: Keys.userAvatarURL)
        
        if !userId.isEmpty {
            currentUser = SupabaseUser(
                id: userId,
                email: email,
                name: name,
                avatarURL: avatarURL
            )
            isAuthenticated = true
            print("✅ [SupabaseAuth] Restored session for: \(name)")
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SupabaseAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Supabase User Model

struct SupabaseUser: Sendable {
    let id: String
    let email: String
    let name: String
    let avatarURL: String?
    
    var displayName: String {
        name.isEmpty ? email : name
    }
    
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        } else if let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }
}
