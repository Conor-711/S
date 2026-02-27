import SwiftUI

// MARK: - Japanese Modern Design Constants
/// Design system inspired by Japanese minimalism - clean, calm, refined
struct CollectionDesign {
    // Colors - Japanese modern palette
    static let background = Color(hex: "F7F6F3")  // Warm paper white
    static let cardBackground = Color.white
    static let accent = Color(hex: "1A1A1A")  // Ink black
    static let accentSoft = Color(hex: "8B7355")  // Warm brown
    static let accentTeal = Color(hex: "5D7A7A")  // Muted blue-green
    static let textPrimary = Color(hex: "1A1A1A")  // Deep black
    static let textSecondary = Color(hex: "8C8C8C")  // Neutral gray
    static let border = Color(hex: "E5E5E5")  // Subtle gray
    static let highlight = Color(hex: "C4A77D")  // Gold accent
    
    // Typography - Serif for titles, clean for body
    static let titleFont = Font.system(size: 14, weight: .medium, design: .serif)
    static let bodyFont = Font.system(size: 12, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 10, weight: .regular)
    
    // Card styling
    static let cardCornerRadius: CGFloat = 12
    static let cardShadow = Color.black.opacity(0.04)
    static let cardShadowRadius: CGFloat = 8
}

// MARK: - Home View
/// Displays captured screenshots and their associated Atoms in a beautiful collection format
struct HomeView: View {
    @StateObject private var historyService = CaptureHistoryService.shared
    @State private var selectedItem: CapturedItem?
    @State private var showingClearConfirm = false
    @State private var viewMode: ViewMode = .grid
    @State private var filterType: FilterType = .all
    
    enum ViewMode {
        case grid, list
    }
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case content = "Notes"
        case todo = "Tasks"
    }
    
    private var filteredItems: [CapturedItem] {
        switch filterType {
        case .all: return historyService.items
        case .content: return historyService.items.filter { $0.atom?.type == .content }
        case .todo: return historyService.items.filter { $0.atom?.type == .todo }
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            CollectionDesign.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Hero Header
                heroHeader
                
                // Filter & View Controls
                controlBar
                
                // Content
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    collectionContent
                }
            }
        }
        .alert("Clear Collection", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                historyService.clearHistory()
            }
        } message: {
            Text("Are you sure you want to clear all collected items? This action cannot be undone.")
        }
    }
    
    // MARK: - Hero Header
    
    private var heroHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Collection")
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundColor(CollectionDesign.textPrimary)
                    
                    Text("Smart capture & organize")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(CollectionDesign.textSecondary)
                }
                
                Spacer()
                
                // Stats
                HStack(spacing: 32) {
                    statItem(count: historyService.items.count, label: "Total")
                    statItem(
                        count: historyService.items.filter { $0.atom?.type == .content }.count,
                        label: "Notes"
                    )
                    statItem(
                        count: historyService.items.filter { $0.atom?.type == .todo }.count,
                        label: "Tasks"
                    )
                }
                
                // Clear button
                if !historyService.items.isEmpty {
                    Button(action: { showingClearConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(CollectionDesign.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(CollectionDesign.border.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear all")
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            
            // Divider
            Rectangle()
                .fill(CollectionDesign.border)
                .frame(height: 1)
        }
        .background(CollectionDesign.cardBackground)
    }
    
    private func statItem(count: Int, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(count)")
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundColor(CollectionDesign.textPrimary)
            
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(CollectionDesign.textSecondary)
        }
    }
    
    // MARK: - Control Bar
    
    private var controlBar: some View {
        HStack(spacing: 0) {
            // Filter tabs
            HStack(spacing: 4) {
                ForEach(FilterType.allCases, id: \.self) { type in
                    filterTab(type)
                }
            }
            
            Spacer()
            
            // View Mode Toggle
            HStack(spacing: 4) {
                viewModeButton(.grid, icon: "square.grid.2x2")
                viewModeButton(.list, icon: "list.bullet")
            }
            .padding(4)
            .background(CollectionDesign.border.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .background(CollectionDesign.background)
    }
    
    private func filterTab(_ type: FilterType) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { filterType = type } }) {
            VStack(spacing: 6) {
                Text(type.rawValue)
                    .font(.system(size: 13, weight: filterType == type ? .medium : .regular))
                    .foregroundColor(filterType == type ? CollectionDesign.textPrimary : CollectionDesign.textSecondary)
                
                // Underline indicator
                Rectangle()
                    .fill(filterType == type ? CollectionDesign.accent : Color.clear)
                    .frame(height: 2)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }
    
    private func viewModeButton(_ mode: ViewMode, icon: String) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { viewMode = mode } }) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(viewMode == mode ? CollectionDesign.textPrimary : CollectionDesign.textSecondary.opacity(0.6))
                .frame(width: 30, height: 28)
                .background(viewMode == mode ? CollectionDesign.cardBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Collection Content
    
    private var collectionContent: some View {
        ScrollView {
            if viewMode == .grid {
                gridView
            } else {
                listView
            }
        }
    }
    
    private var gridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 24)], spacing: 24) {
            ForEach(filteredItems) { item in
                CollectionCardView(item: item, isSelected: selectedItem?.id == item.id)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) {
                            selectedItem = selectedItem?.id == item.id ? nil : item
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            historyService.deleteItem(item)
                            if selectedItem?.id == item.id {
                                selectedItem = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(32)
    }
    
    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredItems) { item in
                CollectionListRowView(item: item, isSelected: selectedItem?.id == item.id)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) {
                            selectedItem = selectedItem?.id == item.id ? nil : item
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            historyService.deleteItem(item)
                            if selectedItem?.id == item.id {
                                selectedItem = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Minimal circle
            ZStack {
                Circle()
                    .stroke(CollectionDesign.border, lineWidth: 1)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bookmark")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundColor(CollectionDesign.textSecondary.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text(filterType == .all ? "Empty Collection" : "No \(filterType.rawValue)")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundColor(CollectionDesign.textPrimary)
                
                Text("Three-finger double tap to capture screen content")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(CollectionDesign.textSecondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Collection Card View

struct CollectionCardView: View {
    let item: CapturedItem
    let isSelected: Bool
    
    @State private var isHovered = false
    @State private var showDetails = false
    @State private var showImagePreview = false
    
    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.capturedAt, relativeTo: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Screenshot - aspect fit to show more content
            ZStack(alignment: .topTrailing) {
                // Screenshot - clickable to view original
                if let screenshot = item.screenshot {
                    Image(nsImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .frame(maxWidth: .infinity)
                        .background(CollectionDesign.background)
                        .onTapGesture {
                            showImagePreview = true
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // Zoom hint on hover
                            if isHovered {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .padding(8)
                            }
                        }
                } else {
                    Rectangle()
                        .fill(CollectionDesign.background)
                        .frame(height: 160)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundColor(CollectionDesign.textSecondary.opacity(0.3))
                        )
                }
                
                // Type badge
                if let atom = item.atom {
                    typeBadge(atom.type)
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CollectionDesign.cardCornerRadius, style: .continuous))
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Title
                if let atom = item.atom {
                    Text(atom.payload.title)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(CollectionDesign.textPrimary)
                        .lineLimit(2)
                } else {
                    Text("Processing...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(CollectionDesign.textSecondary)
                }
                
                // Description
                if let description = item.atom?.payload.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(CollectionDesign.textSecondary)
                        .lineLimit(2)
                }
                
                // Footer
                HStack(spacing: 8) {
                    Text(relativeTime)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(CollectionDesign.textSecondary.opacity(0.7))
                    
                    if let category = item.atom?.payload.category {
                        Text("·")
                            .foregroundColor(CollectionDesign.textSecondary.opacity(0.5))
                        Text(category)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(CollectionDesign.accentTeal)
                    }
                    
                    Spacer()
                    
                    // Expand button
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() } }) {
                        HStack(spacing: 4) {
                            Text(showDetails ? "Less" : "More")
                                .font(.system(size: 10, weight: .regular))
                            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .regular))
                        }
                        .foregroundColor(CollectionDesign.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            
            // Details View (expanded) - Notion-style fields
            if showDetails, let atom = item.atom {
                Divider()
                    .padding(.horizontal, 16)
                
                AtomDetailsView(atom: atom, capturedAt: item.capturedAt)
                    .padding(16)
            }
        }
        .background(CollectionDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CollectionDesign.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CollectionDesign.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? CollectionDesign.accentTeal : CollectionDesign.border,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: CollectionDesign.cardShadow, radius: isHovered ? 12 : CollectionDesign.cardShadowRadius, y: isHovered ? 6 : 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showImagePreview) {
            ImagePreviewSheet(image: item.screenshot, isPresented: $showImagePreview)
        }
    }
    
    private func typeBadge(_ type: AtomType) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(typeColor(for: type))
                .frame(width: 6, height: 6)
            
            Text(typeText(for: type))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(typeColor(for: type))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.95))
        .clipShape(Capsule())
    }
    
    private func typeColor(for type: AtomType) -> Color {
        switch type {
        case .content: return CollectionDesign.accentTeal
        case .todo: return .orange
        case .discard: return .gray
        }
    }
    
    private func typeText(for type: AtomType) -> String {
        switch type {
        case .content: return "Note"
        case .todo: return "Task"
        case .discard: return "Ignored"
        }
    }
}

// MARK: - Collection List Row View

struct CollectionListRowView: View {
    let item: CapturedItem
    let isSelected: Bool
    
    @State private var isHovered = false
    
    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.capturedAt, relativeTo: Date())
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            if let screenshot = item.screenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(CollectionDesign.background)
                    .frame(width: 80, height: 56)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14, weight: .ultraLight))
                            .foregroundColor(CollectionDesign.textSecondary.opacity(0.3))
                    )
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let atom = item.atom {
                        Text(atom.payload.title)
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundColor(CollectionDesign.textPrimary)
                            .lineLimit(1)
                    } else {
                        Text("Processing...")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(CollectionDesign.textSecondary)
                    }
                    
                    Spacer()
                    
                    if let atom = item.atom {
                        typeBadge(atom.type)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(relativeTime)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(CollectionDesign.textSecondary)
                    
                    if let category = item.atom?.payload.category {
                        Text("·")
                            .foregroundColor(CollectionDesign.textSecondary.opacity(0.5))
                        Text(category)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(CollectionDesign.accentTeal)
                    }
                    
                    if let description = item.atom?.payload.description, !description.isEmpty {
                        Text("·")
                            .foregroundColor(CollectionDesign.textSecondary.opacity(0.5))
                        Text(description)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(CollectionDesign.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .background(CollectionDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? CollectionDesign.accentTeal : CollectionDesign.border,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: CollectionDesign.cardShadow, radius: isHovered ? 8 : 4, y: isHovered ? 4 : 1)
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    private func typeBadge(_ type: AtomType) -> some View {
        Circle()
            .fill(typeColor(for: type))
            .frame(width: 8, height: 8)
    }
    
    private func typeColor(for type: AtomType) -> Color {
        switch type {
        case .content: return CollectionDesign.accentTeal
        case .todo: return .orange
        case .discard: return .gray
        }
    }
}

// MARK: - Image Preview Sheet

struct ImagePreviewSheet: View {
    let image: NSImage?
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Screenshot Preview")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CollectionDesign.textPrimary)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CollectionDesign.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(CollectionDesign.border.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(CollectionDesign.cardBackground)
            
            Divider()
            
            // Image
            if let image = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(CollectionDesign.background)
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(CollectionDesign.textSecondary.opacity(0.3))
                    Text("No image available")
                        .font(.system(size: 13))
                        .foregroundColor(CollectionDesign.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CollectionDesign.background)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .frame(maxWidth: 1200, maxHeight: 900)
    }
}

// MARK: - Atom Details View (Notion-style fields)

struct AtomDetailsView: View {
    let atom: Atom
    let capturedAt: Date
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Captured Time
            detailRow(icon: "clock", label: "Captured", value: dateFormatter.string(from: capturedAt))
            
            // Type
            detailRow(icon: "tag", label: "Type", value: typeText(for: atom.type), valueColor: typeColor(for: atom.type))
            
            // Category (for content type)
            if let category = atom.payload.category {
                detailRow(icon: "folder", label: "Category", value: category, valueColor: CollectionDesign.accentTeal)
            }
            
            // Source URL
            if let sourceUrl = atom.payload.sourceUrl, !sourceUrl.isEmpty {
                detailRowWithLink(icon: "link", label: "Source URL", url: sourceUrl)
            }
            
            // Description
            if let description = atom.payload.description, !description.isEmpty {
                detailRowMultiline(icon: "text.alignleft", label: "Description", value: description)
            }
            
            // User Note
            if let userNote = atom.payload.userNote, !userNote.isEmpty {
                detailRowMultiline(icon: "note.text", label: "Note", value: userNote)
            }
            
            // Todo-specific fields
            if atom.type == .todo {
                if let assignee = atom.payload.assigneeName, !assignee.isEmpty {
                    detailRow(icon: "person", label: "Assignee", value: assignee)
                }
                
                if let dueDate = atom.payload.dueDate, !dueDate.isEmpty {
                    detailRow(icon: "calendar", label: "Due Date", value: dueDate, valueColor: .orange)
                }
                
                if let context = atom.payload.todoContext {
                    detailRow(icon: "briefcase", label: "Context", value: context == "work" ? "Work" : "Personal")
                }
            }
            
            // Original capture timestamp from payload
            detailRow(icon: "clock.arrow.circlepath", label: "Payload Time", value: atom.payload.capturedAt)
        }
    }
    
    private func detailRow(icon: String, label: String, value: String, valueColor: Color = CollectionDesign.textPrimary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(CollectionDesign.textSecondary)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CollectionDesign.textSecondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(valueColor)
                .textSelection(.enabled)
        }
    }
    
    private func detailRowWithLink(icon: String, label: String, url: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(CollectionDesign.textSecondary)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CollectionDesign.textSecondary)
                .frame(width: 80, alignment: .leading)
            
            Link(destination: URL(string: url) ?? URL(string: "https://example.com")!) {
                Text(url)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(CollectionDesign.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func detailRowMultiline(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(CollectionDesign.textSecondary)
                    .frame(width: 16)
                
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CollectionDesign.textSecondary)
            }
            
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(CollectionDesign.textPrimary)
                .padding(.leading, 28)
                .textSelection(.enabled)
        }
    }
    
    private func typeText(for type: AtomType) -> String {
        switch type {
        case .content: return "Note"
        case .todo: return "Task"
        case .discard: return "Ignored"
        }
    }
    
    private func typeColor(for type: AtomType) -> Color {
        switch type {
        case .content: return CollectionDesign.accentTeal
        case .todo: return .orange
        case .discard: return .gray
        }
    }
}

// MARK: - Legacy Capture Card View (kept for compatibility)

struct CaptureCardView: View {
    let item: CapturedItem
    let isSelected: Bool
    
    var body: some View {
        CollectionCardView(item: item, isSelected: isSelected)
    }
}

// MARK: - Atom JSON View (kept for debugging)

struct AtomJSONView: View {
    let atom: Atom
    
    @State private var isCopied = false
    
    private var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(atom),
              let string = String(data: data, encoding: .utf8) else {
            return "{ \"error\": \"Failed to encode\" }"
        }
        return string
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Atom JSON")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: copyJSON) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(jsonString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CollectionDesign.textPrimary)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .padding(12)
            .background(Color(hex: "F8F8F8"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .frame(width: 600, height: 500)
}
