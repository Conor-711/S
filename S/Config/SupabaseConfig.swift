import Foundation

// MARK: - Supabase Configuration
// Configure your Supabase project credentials here

enum SupabaseConfig {
    // TODO: Replace with your actual Supabase project credentials
    static let projectURL = "https://tczeneffgkdxdjyhtrtt.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjemVuZWZmZ2tkeGRqeWh0cnR0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1NTM2MTgsImV4cCI6MjA4MzEyOTYxOH0.fOKAcOMot79emzU1vznNQ84Lt0-rBGId71B2K7AWu8Y"
    
    // OAuth callback URL scheme
    static let callbackScheme = "s-navigator"
    static let callbackURL = "\(callbackScheme)://auth/callback"
    
    // Google OAuth provider
    static let googleProvider = "google"
}
