import Foundation

// MARK: - Notion OAuth Configuration
// Configure your Notion public integration credentials here
// Create at: https://www.notion.so/my-integrations

enum NotionOAuthConfig {
    // Notion OAuth credentials
    // Create a public integration at https://www.notion.so/my-integrations
    static let clientId = "2ded872b-594c-80af-9d94-003759a7dcb4"
    static let clientSecret = "secret_zK9mRlFIjqhVJz8Ra1S8U5rApIRzbttqGERp84BlV2a"
    
    // OAuth endpoints
    static let authorizationURL = "https://api.notion.com/v1/oauth/authorize"
    static let tokenURL = "https://api.notion.com/v1/oauth/token"
    
    // Callback URL - Notion requires https:// redirect URI
    // We use Supabase as a proxy to redirect back to the app
    static let callbackScheme = "s-navigator"
    // This is the HTTPS redirect URI registered in Notion (Supabase will redirect to app)
    static let redirectURI = "\(SupabaseConfig.projectURL)/functions/v1/notion-oauth-callback"
    // Final callback to the app
    static let appCallbackURL = "\(callbackScheme)://notion/callback"
    
    // API
    static let apiBaseURL = "https://api.notion.com/v1"
    static let apiVersion = "2022-06-28"
}
