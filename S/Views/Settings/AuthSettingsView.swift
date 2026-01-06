import SwiftUI

// MARK: - Auth Settings View
// User authentication with Google via Supabase

struct AuthSettingsView: View {
    @StateObject private var authService = SupabaseAuthService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if authService.isAuthenticated {
                        userInfoSection
                    } else {
                        signInSection
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 360, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("账户")
                    .font(.headline)
                Text("使用 Google 账号登录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Sign In Section
    
    private var signInSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("登录以同步您的设置和连接")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: signInWithGoogle) {
                HStack {
                    if authService.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 20))
                    }
                    
                    Text("使用 Google 登录")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isAuthenticating)
            
            if let error = authService.authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - User Info Section
    
    private var userInfoSection: some View {
        VStack(spacing: 16) {
            // Avatar
            if let user = authService.currentUser {
                if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        initialsAvatar(user.initials)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                } else {
                    initialsAvatar(user.initials)
                }
                
                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.headline)
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Sign out button
            Button(action: signOut) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("退出登录")
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private func initialsAvatar(_ initials: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 64, height: 64)
            .overlay(
                Text(initials)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Spacer()
            
            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
    
    // MARK: - Actions
    
    private func signInWithGoogle() {
        Task {
            let success = await authService.signInWithGoogle()
            if success {
                print("✅ [AuthSettings] Google sign in successful")
            }
        }
    }
    
    private func signOut() {
        authService.signOut()
    }
}

// MARK: - Preview

#Preview {
    AuthSettingsView()
}
