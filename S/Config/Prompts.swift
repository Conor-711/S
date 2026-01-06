import Foundation

// MARK: - V13: Simplified Prompts
// Removed: TR-P-D architecture prompts, step generation, URL ingestion
// Kept: Visual note analysis prompts for Knowledge Base

enum AgentPrompts {
    
    // MARK: - Visual Note Analysis (V9 Knowledge Base)
    
    /// Analyze screenshot for visual note capture
    static func visualNoteAnalysisPrompt() -> String {
        """
        [TASK]
        Analyze this screenshot for a Personal Knowledge Base.
        The user saved this because they found it interesting or useful.
        
        [OUTPUT JSON]
        {
          "caption": "Brief description of the content (e.g., A Python script for web scraping using BeautifulSoup).",
          "intent": "Why the user saved this (e.g., Reference for future coding, UI design inspiration, error log)."
        }
        
        IMPORTANT: Return ONLY valid JSON, no other text.
        """
    }
    
    /// Generate knowledge report from collected notes
    static func knowledgeReportPrompt(notesInput: String, timeRange: String) -> String {
        """
        [TASK]
        Synthesize these visual notes into a coherent Knowledge Report.
        The user captured these screenshots in sequence.
        Group them logically (e.g., "Design Inspiration", "Code Snippets").
        Deduplicate if multiple notes seem to describe the same static screen.
        
        [NOTES]
        \(notesInput)
        
        [TIME RANGE]
        \(timeRange)
        
        [OUTPUT FORMAT]
        Markdown.
        Structure:
        # Visual Session Report [Date]
        ## Summary
        ...
        ## Key Insights
        - [Intent]: [Caption details]
        ...
        
        Return ONLY the markdown report, no JSON wrapper.
        """
    }
    
    // MARK: - General Screen Analysis
    
    /// General screen analysis prompt
    static func screenAnalysisPrompt(customPrompt: String? = nil) -> String {
        customPrompt ?? """
        Analyze this screenshot and describe what you see in detail.
        Include:
        - The application or website visible
        - Key UI elements and their state
        - Any text content that appears important
        - The overall context of what the user is doing
        """
    }
    
    // MARK: - V1.1 Visual ETL Prompt
    
    /// Visual ETL prompt for structured data extraction
    /// Extracts content or todo items from screenshots
    /// V1.2: Now accepts optional user note for AI enhancement
    static func visualETLPrompt(currentDate: String, userNote: String? = nil) -> String {
        let userNoteSection: String
        if let note = userNote, !note.isEmpty {
            userNoteSection = """
            
            [USER NOTE]
            The user provided this note about the screenshot: "\(note)"
            
            Your task for the user_note field:
            - Enhance the user's note to make it more descriptive and useful for future recall
            - Add context from the screenshot that connects to what the user mentioned
            - Keep the enhanced note concise but informative (under 200 characters)
            - If the user's note references something specific (like "PG" meaning Paul Graham), expand it naturally
            - Preserve the user's original intent while making it more searchable and memorable
            
            """
        } else {
            userNoteSection = ""
        }
        
        return """
        You are a Visual ETL engine. Your job is to extract structured data from a screenshot for a Notion database.
        Current System Time: \(currentDate)
        \(userNoteSection)
        Rules:
        1. Analyze the image content and Determine the TYPE:
           - "todo": If it looks like a task, request, or has a deadline.
           - "content": If it is informational content related to "AI", "Design", or "Product".
           - "discard": If it is a meme, personal chat, irrelevant news, or does not fit "AI/Design/Product".

        2. If TYPE is "content":
           - Extract a summary as 'title'.
           - Extract details as 'description'.
           - Classify 'category' strictly into one of: ["AI", "Design", "Product"].
           - Extract 'source_url' if any URL is visible in the screenshot.

        3. If TYPE is "todo":
           - Extract the task name as 'title'.
           - Extract details as 'description'.
           - Extract 'assignee_name' (just the name text) if present.
           - Calculate 'due_date' based on Current System Time if mentioned (e.g., "next Friday"). Return YYYY-MM-DD format.
           - **IMPORTANT**: Classify 'todo_context' as either:
             - "work": Work-related tasks (meetings, project deadlines, team tasks, Slack messages, emails from colleagues, Jira/Linear tickets, code reviews, etc.)
             - "life": Personal tasks (shopping, appointments, personal reminders, family matters, hobbies, etc.)

        4. If a USER NOTE was provided, enhance it as described above and include in 'user_note'.

        5. Output ONLY valid JSON matching this schema:
        {
          "type": "content" | "todo" | "discard",
          "title": "string",
          "description": "string or null",
          "category": "AI" | "Design" | "Product" | null,
          "source_url": "string or null",
          "assignee_name": "string or null",
          "due_date": "YYYY-MM-DD or null",
          "todo_context": "work" | "life" | null,
          "user_note": "string or null"
        }

        IMPORTANT: Return ONLY valid JSON, no other text or markdown.
        """
    }
}
