import SwiftUI

// MARK: - Main Settings View
// Central settings window containing all configuration options:
// - Google/Supabase authentication
// - Connectors (Notion, and future integrations)
// V1.2: Removed ETL tab - auto-initializes when Notion connects

struct MainSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    let connectorService: ConnectorService
    
    @StateObject private var authService = SupabaseAuthService.shared
    @StateObject private var oauthService = NotionOAuth2Service.shared
    @State private var schemaState = NotionSchemaState.shared
    
    @State private var selectedTab: SettingsTab = .home
    @State private var isInitializingETL: Bool = false
    @State private var etlStatusMessage: String?
    
    enum SettingsTab: String, CaseIterable {
        case home = "首页"
        case account = "账户"
        case connectors = "Connectors"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .account: return "person.circle.fill"
            case .connectors: return "link.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
            
            Divider()
            
            // Content
            VStack(spacing: 0) {
                contentView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1100, height: 780)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
            
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))
                            .frame(width: 24)
                        
                        Text(tab.rawValue)
                            .font(.body)
                        
                        Spacer()
                        
                        // Status indicator
                        statusIndicator(for: tab)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // Version info
            Text("S v1.3")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(16)
        }
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func statusIndicator(for tab: SettingsTab) -> some View {
        Group {
            switch tab {
            case .home:
                // Show count badge
                let count = CaptureHistoryService.shared.items.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                } else {
                    EmptyView()
                }
            case .account:
                Circle()
                    .fill(authService.isAuthenticated ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            case .connectors:
                // Show green if any connector is connected
                Circle()
                    .fill(oauthService.isAuthenticated ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .account:
            accountContent
        case .connectors:
            connectorsContent
        }
    }
    
    // MARK: - Account Content
    
    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            sectionHeader(title: "账户", subtitle: "使用 Google 账号登录同步设置", icon: "person.circle.fill")
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if authService.isAuthenticated {
                        // User info
                        HStack(spacing: 16) {
                            if let user = authService.currentUser, let avatarURL = user.avatarURL {
                                AsyncImage(url: URL(string: avatarURL)) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(authService.currentUser?.displayName ?? "用户")
                                    .font(.title3.weight(.semibold))
                                
                                if let email = authService.currentUser?.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        
                        Button("退出登录") {
                            Task { await authService.signOut() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        // Sign in prompt
                        VStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("登录以同步您的设置")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Button(action: signInWithGoogle) {
                                HStack {
                                    if authService.isAuthenticating {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "g.circle.fill")
                                        Text("使用 Google 登录")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(authService.isAuthenticating)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - Connectors Content
    
    private var connectorsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            sectionHeader(title: "Connectors", subtitle: "连接第三方应用", icon: "link.circle.fill")
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Notion Connector
                    notionConnectorCard
                    
                    // Obsidian Connector (Coming Soon)
                    obsidianConnectorCard
                    
                    // Future connectors placeholder
                    comingSoonConnectors
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - Notion Connector Card
    
    private var notionConnectorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.black, .gray],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notion")
                        .font(.headline)
                    Text("截图自动分类存储")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status badge
                if oauthService.isAuthenticated {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("已连接")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            
            Divider()
            
            if oauthService.isAuthenticated {
                // Connected state
                VStack(alignment: .leading, spacing: 12) {
                    if let workspace = oauthService.workspaceName {
                        HStack {
                            Text("工作区")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(workspace)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                    }
                    
                    // ETL Status
                    HStack {
                        Text("数据库状态")
                            .foregroundColor(.secondary)
                        Spacer()
                        if isInitializingETL {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("初始化中...")
                                .font(.caption)
                        } else if schemaState.isComplete {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已就绪")
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("未配置")
                            }
                        }
                    }
                    .font(.subheadline)
                    
                    if let message = etlStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(schemaState.isComplete ? .green : .orange)
                    }
                    
                    Divider()
                    
                    // Actions
                    HStack {
                        if !schemaState.isComplete {
                            Button(action: initializeETL) {
                                Label("初始化数据库", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInitializingETL)
                        }
                        
                        Spacer()
                        
                        Button("断开连接") {
                            disconnectNotion()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            } else {
                // Not connected state
                VStack(spacing: 12) {
                    Text("连接 Notion 后，三指双击截图将自动分类并存储到您的 Notion 数据库")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: connectNotion) {
                        HStack {
                            Image(systemName: "link")
                            Text("连接 Notion")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Obsidian Connector Card (V1.3)
    
    private var obsidianConnectorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Obsidian")
                        .font(.headline)
                    Text("本地知识库同步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Coming soon badge
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("即将支持")
                        .font(.caption)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            Divider()
            
            // Coming soon state
            VStack(spacing: 12) {
                Text("连接 Obsidian 后，截图内容将自动保存到您的本地知识库")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: {}) {
                    HStack {
                        Image(systemName: "link")
                        Text("连接 Obsidian")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(true)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Coming Soon Connectors
    
    private var comingSoonConnectors: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("即将支持")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                comingSoonItem(name: "Linear", icon: "line.3.horizontal")
                comingSoonItem(name: "Slack", icon: "number.square")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private func comingSoonItem(name: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .opacity(0.5)
    }
    
    
    // MARK: - Helpers
    
    private func sectionHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Actions
    
    private func signInWithGoogle() {
        Task {
            await authService.signInWithGoogle()
        }
    }
    
    // MARK: - Notion Actions
    
    private func connectNotion() {
        Task {
            await oauthService.startOAuthFlow()
            // Auto-initialize ETL after connecting
            if oauthService.isAuthenticated && !schemaState.isComplete {
                await initializeETLAsync()
            }
        }
    }
    
    private func disconnectNotion() {
        oauthService.disconnect()
        NotionSchemaState.shared.clear()
        schemaState = NotionSchemaState.shared
        etlStatusMessage = nil
    }
    
    private func initializeETL() {
        Task {
            await initializeETLAsync()
        }
    }
    
    private func initializeETLAsync() async {
        isInitializingETL = true
        etlStatusMessage = nil
        
        do {
            let pipeline = PipelineController(
                llmService: GeminiLLMService(),
                captureService: ScreenCaptureService()
            )
            try await pipeline.initializeSchema()
            
            await MainActor.run {
                isInitializingETL = false
                etlStatusMessage = "数据库初始化成功"
                schemaState = NotionSchemaState.shared
            }
        } catch {
            await MainActor.run {
                isInitializingETL = false
                etlStatusMessage = "初始化失败: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainSettingsView(
        connectorService: ConnectorService(
            captureService: ScreenCaptureService(),
            llmService: GeminiLLMService()
        )
    )
}
