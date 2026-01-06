import SwiftUI

// MARK: - Notion Settings View
// Allows user to configure Notion MCP target page/database

struct NotionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    let connectorService: ConnectorService
    @State private var settings = MCPSettings.shared
    @StateObject private var oauthService = NotionOAuth2Service.shared
    
    @State private var isConnecting: Bool = false
    @State private var isSearching: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [NotionPageInfo] = []
    @State private var errorMessage: String?
    @State private var showingOAuthAlert: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionSection
                    
                    if settings.isNotionConnected {
                        targetSection
                        searchSection
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Notion 设置")
                    .font(.headline)
                Text("配置 MCP 连接和目标页面")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("连接状态", systemImage: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack {
                Circle()
                    .fill(oauthService.isAuthenticated ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(oauthService.isAuthenticated ? "已连接" : "未连接")
                        .font(.body)
                    
                    if oauthService.isAuthenticated, let workspaceName = oauthService.workspaceName {
                        Text(workspaceName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if settings.isNotionConnected {
                    Button("断开连接") {
                        disconnectNotion()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button(action: connectNotion) {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Text("连接 Notion")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Target Section
    
    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("目标位置", systemImage: "folder")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("保存笔记到")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(settings.notionTargetDisplayName)
                        .font(.body)
                }
                
                Spacer()
                
                if settings.hasNotionTarget {
                    Button("清除") {
                        settings.notionTargetPageId = nil
                        settings.notionTargetPageTitle = nil
                        settings.notionTargetDatabaseId = nil
                        settings.notionTargetDatabaseTitle = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("搜索页面或数据库", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack {
                TextField("输入关键词搜索...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        searchNotion()
                    }
                
                Button(action: searchNotion) {
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(searchQuery.isEmpty || isSearching)
            }
            
            // Search Results
            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { page in
                        Button(action: {
                            selectPage(page)
                        }) {
                            HStack {
                                Text(page.displayIcon)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Text(page.isDatabase ? "数据库" : "页面")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if isSelected(page) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(10)
                            .background(isSelected(page) ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        
                        if page.id != searchResults.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
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
    
    private func connectNotion() {
        isConnecting = true
        errorMessage = nil
        
        Task {
            // First try to connect with existing token (if any)
            let success = await connectorService.testNotionConnection()
            
            if success {
                await MainActor.run {
                    isConnecting = false
                    settings.isNotionConnected = true
                }
                return
            }
            
            // If connection failed, start OAuth flow in browser
            print("🔐 [NotionSettings] Starting browser OAuth flow...")
            let oauthSuccess = await oauthService.startOAuthFlow()
            
            await MainActor.run {
                isConnecting = false
                
                if oauthSuccess {
                    settings.isNotionConnected = true
                    // Try to verify connection after OAuth
                    Task {
                        let verified = await connectorService.testNotionConnection()
                        if verified {
                            print("✅ [NotionSettings] OAuth verified successfully")
                        }
                    }
                } else {
                    errorMessage = oauthService.authError ?? "授权失败，请重试"
                }
            }
        }
    }
    
    private func disconnectNotion() {
        oauthService.disconnect()
        searchResults = []
        searchQuery = ""
    }
    
    private func searchNotion() {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await connectorService.searchNotion(query: searchQuery)
                
                await MainActor.run {
                    isSearching = false
                    
                    // Convert NotionSearchResult to NotionPageInfo array
                    var pages: [NotionPageInfo] = []
                    
                    for page in result.pages {
                        pages.append(NotionPageInfo(id: page.id, title: page.title, icon: page.icon, isDatabase: false))
                    }
                    
                    for db in result.databases {
                        pages.append(NotionPageInfo(id: db.id, title: db.title, icon: db.icon, isDatabase: true))
                    }
                    
                    searchResults = pages
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func selectPage(_ page: NotionPageInfo) {
        if page.isDatabase {
            settings.setNotionTargetDatabase(id: page.id, title: page.title)
        } else {
            settings.setNotionTargetPage(id: page.id, title: page.title)
        }
    }
    
    private func isSelected(_ page: NotionPageInfo) -> Bool {
        if page.isDatabase {
            return settings.notionTargetDatabaseId == page.id
        } else {
            return settings.notionTargetPageId == page.id
        }
    }
}

// MARK: - Preview

#Preview {
    NotionSettingsView(
        connectorService: ConnectorService(
            captureService: ScreenCaptureService(),
            llmService: GeminiLLMService()
        )
    )
}
