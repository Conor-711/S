import SwiftUI

// MARK: - V1.1 ETL Settings View
// Configure Visual ETL pipeline: root page selection and database initialization

struct ETLSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    let connectorService: ConnectorService
    @State private var schemaState = NotionSchemaState.shared
    @StateObject private var oauthService = NotionOAuth2Service.shared
    
    @State private var isSearching: Bool = false
    @State private var isInitializing: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [NotionPageInfo] = []
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    // Selected parent page (where "S" will be created)
    @State private var selectedParentPageId: String?
    @State private var selectedParentPageTitle: String?
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    
                    if oauthService.isAuthenticated {
                        if schemaState.isComplete {
                            // Already configured - show current state
                            configuredSection
                        } else {
                            // Not configured - show setup flow
                            parentPageSection
                            
                            if selectedParentPageId != nil {
                                createSection
                            }
                        }
                    } else {
                        notConnectedSection
                    }
                }
                .padding(20)
            }
            
            Divider()
            footer
        }
        .frame(width: 420, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Visual ETL 设置")
                    .font(.headline)
                Text("配置截图到 Notion 的自动分类存储")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("配置状态", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schemaState.statusDescription)
                        .font(.body)
                    
                    if schemaState.isComplete {
                        Text("Content → \(schemaState.contentDbId?.prefix(8) ?? "")...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Todo → \(schemaState.todoDbId?.prefix(8) ?? "")...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if schemaState.isComplete {
                    Button("重置") {
                        resetSchema()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Not Connected Section
    
    private var notConnectedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("需要连接 Notion", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            
            Text("请先在 Notion 设置中连接您的 Notion 账户")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }
    
    // MARK: - Configured Section (when setup is complete)
    
    private var configuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已配置完成", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("📸")
                    Text("S 页面")
                        .font(.body)
                    Spacer()
                    Text(schemaState.rootPageId?.prefix(8) ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("📚")
                    Text("Visual Knowledge")
                        .font(.body)
                    Spacer()
                    Text("Content")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("✅")
                    Text("Visual Tasks")
                        .font(.body)
                    Spacer()
                    Text("Todo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Button("重置配置") {
                resetSchema()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
    
    // MARK: - Parent Page Section (step 1: select where to create "S")
    
    private var parentPageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1. 选择父页面", systemImage: "folder")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            if let parentTitle = selectedParentPageTitle {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(parentTitle)
                        .font(.body)
                    Spacer()
                    Button("更换") {
                        selectedParentPageId = nil
                        selectedParentPageTitle = nil
                        searchResults = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择一个页面，系统将在其中创建新的 \"S\" 页面和数据库")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("搜索页面...", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { searchPages() }
                        
                        Button(action: searchPages) {
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
                    
                    if !searchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(searchResults.filter { !$0.isDatabase }) { page in
                                Button(action: { selectParentPage(page) }) {
                                    HStack {
                                        Text(page.displayIcon)
                                            .font(.title3)
                                        Text(page.title)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(10)
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
        }
    }
    
    // MARK: - Create Section (step 2: create S page and databases)
    
    private var createSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("2. 创建 ETL 结构", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("将在选中的页面中创建：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 📸 **S** - 新页面作为 ETL 根目录")
                    Text("• 📚 **Visual Knowledge** - Content 数据库")
                    Text("• ✅ **Visual Tasks** - Todo 数据库")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Button(action: createETLStructure) {
                    if isInitializing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("创建中...")
                        }
                    } else {
                        Text("创建 ETL 结构")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInitializing)
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if let success = successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            if schemaState.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已就绪")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
    
    // MARK: - Actions
    
    private func searchPages() {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await connectorService.searchNotion(query: searchQuery)
                
                await MainActor.run {
                    isSearching = false
                    var pages: [NotionPageInfo] = []
                    
                    for page in result.pages {
                        pages.append(NotionPageInfo(id: page.id, title: page.title, icon: page.icon, isDatabase: false))
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
    
    private func selectParentPage(_ page: NotionPageInfo) {
        selectedParentPageId = page.id
        selectedParentPageTitle = page.title
        searchResults = []
        searchQuery = ""
    }
    
    private func createETLStructure() {
        guard let parentId = selectedParentPageId else { return }
        
        isInitializing = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                let pipeline = PipelineController(
                    llmService: GeminiLLMService(),
                    captureService: ScreenCaptureService()
                )
                try await pipeline.initializeSchema(parentPageId: parentId)
                
                await MainActor.run {
                    isInitializing = false
                    successMessage = "ETL 结构创建成功！"
                    // Clear selection after success
                    selectedParentPageId = nil
                    selectedParentPageTitle = nil
                }
            } catch {
                await MainActor.run {
                    isInitializing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func resetSchema() {
        schemaState.clear()
        selectedParentPageId = nil
        selectedParentPageTitle = nil
        searchResults = []
        searchQuery = ""
        successMessage = nil
        errorMessage = nil
    }
}

// MARK: - Preview

#Preview {
    ETLSettingsView(
        connectorService: ConnectorService(
            captureService: ScreenCaptureService(),
            llmService: GeminiLLMService()
        )
    )
}
