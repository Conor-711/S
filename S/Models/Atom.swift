import Foundation

// MARK: - V1.1 Visual ETL Data Models
// Core data structure for VLM analysis output

/// Type of content extracted from screenshot
enum AtomType: String, Codable, Sendable {
    case content  // Informational content (AI, Design, Product)
    case todo     // Task or action item with deadline
    case discard  // Irrelevant content (memes, personal chat, etc.)
}

/// V1.2: Context for todo items - determines routing destination
enum TodoContext: String, Codable, Sendable {
    case work     // Work-related todo -> routes to Slack
    case life     // Personal/life todo -> routes to Notion
}

/// Category for content type atoms
enum ContentCategory: String, Codable, Sendable, CaseIterable {
    case ai = "AI"
    case design = "Design"
    case product = "Product"
}

/// Main data structure for VLM analysis result
struct Atom: Codable, Sendable {
    let type: AtomType
    let payload: AtomPayload
}

/// Payload containing extracted data from screenshot
struct AtomPayload: Codable, Sendable {
    // Common semantic fields (AI generated)
    let title: String
    let description: String?
    
    // Content-specific fields
    let category: String?      // "AI", "Design", "Product"
    let sourceUrl: String?     // URL extracted from screenshot content
    
    // Todo-specific fields
    let assigneeName: String?  // Person name text
    let dueDate: String?       // ISO 8601 format (YYYY-MM-DD)
    let todoContext: String?   // V1.2: "work" or "life" - determines routing
    
    // User note (AI enhanced)
    let userNote: String?      // User's note, enhanced by AI for better recall
    
    // Metadata (client injected)
    let capturedAt: String     // ISO 8601 timestamp
    
    // MARK: - Convenience Initializers
    
    /// Create a content atom payload
    static func content(
        title: String,
        description: String?,
        category: String?,
        sourceUrl: String?,
        userNote: String? = nil,
        capturedAt: Date = Date()
    ) -> AtomPayload {
        AtomPayload(
            title: title,
            description: description,
            category: category,
            sourceUrl: sourceUrl,
            assigneeName: nil,
            dueDate: nil,
            todoContext: nil,
            userNote: userNote,
            capturedAt: ISO8601DateFormatter().string(from: capturedAt)
        )
    }
    
    /// Create a todo atom payload
    static func todo(
        title: String,
        description: String?,
        assigneeName: String?,
        dueDate: String?,
        todoContext: String? = nil,
        userNote: String? = nil,
        capturedAt: Date = Date()
    ) -> AtomPayload {
        AtomPayload(
            title: title,
            description: description,
            category: nil,
            sourceUrl: nil,
            assigneeName: assigneeName,
            dueDate: dueDate,
            todoContext: todoContext,
            userNote: userNote,
            capturedAt: ISO8601DateFormatter().string(from: capturedAt)
        )
    }
    
    /// V1.2: Check if this is a work-related todo
    var isWorkTodo: Bool {
        return todoContext?.lowercased() == "work"
    }
    
    /// V1.2: Check if this is a life-related todo
    var isLifeTodo: Bool {
        return todoContext?.lowercased() == "life" || todoContext == nil
    }
}

// MARK: - VLM Response Model

/// Raw response from VLM for parsing
struct AtomVLMResponse: Codable {
    let type: String
    let title: String
    let description: String?
    let category: String?
    let sourceUrl: String?
    let assigneeName: String?
    let dueDate: String?
    let todoContext: String?   // V1.2: "work" or "life"
    let userNote: String?      // AI-enhanced user note
    
    enum CodingKeys: String, CodingKey {
        case type
        case title
        case description
        case category
        case sourceUrl = "source_url"
        case assigneeName = "assignee_name"
        case dueDate = "due_date"
        case todoContext = "todo_context"
        case userNote = "user_note"
    }
    
    /// Convert to Atom with validation
    func toAtom(capturedAt: Date = Date()) -> Atom? {
        guard let atomType = AtomType(rawValue: type.lowercased()) else {
            print("⚠️ [Atom] Unknown type: \(type), treating as discard")
            return Atom(
                type: .discard,
                payload: AtomPayload(
                    title: title,
                    description: description,
                    category: nil,
                    sourceUrl: nil,
                    assigneeName: nil,
                    dueDate: nil,
                    todoContext: nil,
                    userNote: nil,
                    capturedAt: ISO8601DateFormatter().string(from: capturedAt)
                )
            )
        }
        
        // Validate date format for todo
        var validatedDueDate: String? = nil
        if let dueDate = dueDate {
            validatedDueDate = validateDateFormat(dueDate)
        }
        
        // Validate category for content
        var validatedCategory: String? = nil
        if let category = category {
            validatedCategory = validateCategory(category)
        }
        
        // V1.2: Validate todo context
        var validatedTodoContext: String? = nil
        if let context = todoContext {
            validatedTodoContext = validateTodoContext(context)
        }
        
        let payload = AtomPayload(
            title: title,
            description: description,
            category: validatedCategory,
            sourceUrl: sourceUrl,
            assigneeName: assigneeName,
            dueDate: validatedDueDate,
            todoContext: validatedTodoContext,
            userNote: userNote,
            capturedAt: ISO8601DateFormatter().string(from: capturedAt)
        )
        
        return Atom(type: atomType, payload: payload)
    }
    
    /// Validate date format (YYYY-MM-DD)
    private func validateDateFormat(_ date: String) -> String? {
        let pattern = #"^\d{4}-\d{2}-\d{2}$"#
        if date.range(of: pattern, options: .regularExpression) != nil {
            return date
        }
        print("⚠️ [Atom] Invalid date format: \(date), ignoring")
        return nil
    }
    
    /// Validate category against allowed values
    private func validateCategory(_ category: String) -> String? {
        let validCategories = ["AI", "Design", "Product"]
        if validCategories.contains(category) {
            return category
        }
        // Try case-insensitive match
        if let match = validCategories.first(where: { $0.lowercased() == category.lowercased() }) {
            return match
        }
        print("⚠️ [Atom] Invalid category: \(category), ignoring")
        return nil
    }
    
    /// V1.2: Validate todo context against allowed values
    private func validateTodoContext(_ context: String) -> String? {
        let validContexts = ["work", "life"]
        let lowerContext = context.lowercased()
        if validContexts.contains(lowerContext) {
            return lowerContext
        }
        print("⚠️ [Atom] Invalid todo context: \(context), defaulting to life")
        return "life"
    }
}
