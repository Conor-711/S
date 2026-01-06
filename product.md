# S - AI Navigator Codebase Structure (V1.2 User Note)

> **Purpose**: This document provides a comprehensive overview of the project architecture for efficient context loading in new conversations.

---

## 📋 Project Overview

**S** is a macOS AI Navigator application that provides visual note capture, VLM-based screen analysis, and **Visual ETL** (Extract-Transform-Load) for automatic Notion synchronization.

**Current Version**: V1.2 - User Note Enhancement + Slack Integration. Adds user note input during capture with AI enhancement for better recall. Users can hover on the floating panel within 2 seconds after capture to add notes. Work-related todos automatically route to Slack, while life-related todos and content go to Notion.

**Tech Stack**:
- **Language**: Swift (SwiftUI + AppKit)
- **Platform**: macOS (native app)
- **AI Services**: Google Gemini 2.0 Flash (VLM)
- **Backend**: Supabase (OAuth, Edge Functions)
- **Integration**: Notion API (OAuth 2.0), Slack API (OAuth 2.0 + Incoming Webhooks)
- **Architecture**: MVVM
- **Key Features**: Screen capture, gesture triggers, Visual ETL pipeline, VLM-based classification, Notion auto-sync

---

## 🏗️ Architecture Overview

### Core Features

1. **Screen Capture**: Capture screenshots via three-finger double-tap gesture
2. **VLM Analysis**: Google Gemini 2.0 Flash for image understanding and content extraction
3. **Visual ETL Pipeline**: Capture → Atomize → Fit → Notion/Slack (structured data extraction with smart routing)
4. **Notion Integration**: OAuth 2.0 authentication with automatic sync to dedicated databases
5. **Slack Integration**: OAuth 2.0 authentication with automatic work todo posting to configured channel
6. **Google OAuth**: User authentication via Supabase
7. **Main Settings Window**: Unified settings interface with Connectors tab

### Key Components

- **Living Orb UI**: Floating HUD with morphing animation (capture feedback)
- **MainSettingsView**: Unified settings window (Account, Notion, Visual ETL)
- **PipelineController**: Visual ETL orchestrator (Capture → Atomize → Fit → Notion)
- **KnowledgeBaseService**: Visual note capture, VLM analysis, and ETL integration
- **NotionAPIClient**: Direct Notion API integration for creating pages, databases, and entries
- **NotionSchemaState**: Persistent storage for ETL database IDs
- **NotionOAuth2Service**: OAuth 2.0 authentication flow with browser-based authorization
- **SlackOAuthService**: OAuth 2.0 authentication for Slack workspace integration
- **SupabaseAuthService**: Google OAuth login via Supabase
- **InputMonitor**: Three-finger double-tap gesture detection
- **CaptureWindowState**: Shared state for capture window and input mode management

---

## 📁 Directory Structure

```
S/
├── App/                          # Application entry point & lifecycle
│   ├── AI_Navigator_App.swift    # @main entry, AppDelegate
│   └── AppState.swift            # Global state manager, service orchestration
│
├── Models/                       # Data structures & domain models
│   ├── AIModels.swift            # Visual note analysis models
│   ├── VisualNote.swift          # Knowledge base note model
│   ├── CaptureEvent.swift        # Capture animation event
│   ├── ConnectorModels.swift     # Intent classification models
│   ├── MCPSettings.swift         # Notion connection settings
│   ├── Atom.swift                # V1.1: ETL data model (AtomType, AtomPayload, TodoContext)
│   ├── NotionSchemaState.swift   # V1.1: ETL database IDs storage
│   └── CaptureWindowState.swift  # V1.2: Capture window & input mode state
│
├── Config/
│   ├── Prompts.swift             # VLM analysis prompts
│   ├── Secrets.swift             # API keys (Gemini, Grok)
│   ├── SupabaseConfig.swift      # Supabase project configuration
│   └── NotionOAuthConfig.swift   # Notion OAuth credentials
│
├── Services/                     # Business logic & external integrations
│   ├── KnowledgeBaseService.swift # Visual note capture, analysis & ETL integration
│   ├── PipelineController.swift   # V1.1: Visual ETL orchestrator
│   ├── ScreenManager.swift        # Multi-monitor support
│   │
│   ├── Capture/
│   │   ├── ScreenCaptureService.swift  # Screen recording & polling
│   │   └── ImageDiffer.swift           # Visual change detection
│   │
│   ├── Network/
│   │   ├── LLMServiceProtocol.swift    # LLM service interface
│   │   └── GeminiLLMService.swift      # Google Gemini 2.0 Flash integration
│   │
│   ├── Auth/
│   │   ├── SupabaseAuthService.swift   # Google OAuth via Supabase
│   │   ├── NotionOAuthService2.swift   # Notion OAuth 2.0 flow
│   │   └── SlackOAuthService.swift     # V1.2: Slack OAuth 2.0 flow
│   │
│   ├── Notion/
│   │   └── NotionAPIClient.swift       # Direct Notion API client
│   │
│   ├── MCP/
│   │   ├── MCPProtocol.swift           # MCP JSON-RPC types
│   │   ├── NotionMCPClient.swift       # Notion MCP client (legacy)
│   │   ├── IntentClassificationService.swift
│   │   ├── ActionRouter.swift
│   │   └── ConnectorService.swift
│   │
│   └── Voice/
│       ├── InputMonitor.swift          # Three-finger double-tap detection
│       └── KeyMonitor.swift            # fn key monitoring
│
├── Views/                        # SwiftUI UI components
│   ├── FloatingPanel/
│   │   ├── FloatingPanelController.swift  # NSPanel window controller
│   │   └── MorphingHUDView.swift          # Living Orb UI with capture animation
│   │
│   ├── Settings/
│   │   ├── MainSettingsView.swift         # V1.1: Unified settings window
│   │   ├── AuthSettingsView.swift         # Google OAuth login UI
│   │   ├── NotionSettingsView.swift       # Notion connection & target selection
│   │   └── ETLSettingsView.swift          # V1.1: Visual ETL configuration
│   │
│   └── Components/
│       ├── OrbView.swift                  # Living Orb (idle state)
│       ├── CollectionBoxView.swift        # Knowledge base counter
│       ├── StatusIndicator.swift          # Processing state indicator
│       └── VisualEffectView.swift         # macOS visual effects bridge
│
├── Assets.xcassets/               # App icons & assets
├── ContentView.swift              # Unused placeholder view
└── S.entitlements                 # macOS permissions
```

---

## 🔑 Key Components Deep Dive

### 1. **AppState.swift** - Global Orchestrator

**Role**: Central state manager that wires all services together

**Key Responsibilities**:
- Initializes all services (capture, LLM, knowledge base, ETL pipeline)
- Manages session lifecycle (start/stop/reset)
- Handles gesture triggers (Three-Finger Double-Tap)
- Binds service publishers to UI state

**Critical Services Managed**:
```swift
let captureService: ScreenCaptureService
let llmService: GeminiLLMService
let keyMonitor: GlobalKeyMonitor
let knowledgeBaseService: KnowledgeBaseService
let inputMonitor: InputMonitor
let connectorService: ConnectorService
let pipelineController: PipelineController  // V1.1: Visual ETL
```

**Flow**:
1. Three-finger double-tap → `captureVisualNote()` → VLM analysis → ETL Pipeline → Notion
2. Report generation → `generateKnowledgeReport()` → clipboard

---

### 2. **KnowledgeBaseService.swift** - Visual Knowledge Base

**Role**: Capture & synthesize visual notes for personal knowledge management

**Workflow**:
1. **Capture**: User triggers three-finger double-tap
2. **Analyze**: Screenshot sent to Gemini VLM for caption + intent extraction
3. **Store**: Only text metadata saved (image discarded - ephemeral processing)
4. **ETL**: If schema configured, route to PipelineController for structured extraction
5. **Sync**: Auto-save to appropriate Notion database (Content or Todo)
6. **Synthesize**: Generate markdown report from collected notes

**Key Methods**:
- `captureVisualNote()`: Capture → VLM analysis → ETL Pipeline → Notion
- `generateReport()`: Synthesize notes into markdown
- `generateReportAndCopy()`: Generate + clipboard copy

**V1.1 Enhancement**: Integrates with `PipelineController` for Visual ETL when schema is configured

---

### 2.1 **PipelineController.swift** - Visual ETL Orchestrator (V1.1)

**Role**: Orchestrate the Visual ETL pipeline: Capture → Atomize → Fit → Notion/Slack

**Workflow**:
1. **Atomize**: VLM analyzes screenshot with `visualETLPrompt`
2. **Classify**: Determine type (content, todo, discard) and todo context (work/life)
3. **Fit**: Route to appropriate destination based on type and context
4. **Execute**: Save to Notion database or post to Slack channel

**Key Methods**:
- `initializeSchema()`: Create "S" page + databases in Notion (workspace-level)
- `execute(screenshot:userNote:)`: Full ETL pipeline execution with retry mechanism (max 3 attempts)
- `atomize(screenshot:userNote:)`: VLM analysis with structured output and note enhancement
- `isRetryableError()`: Check if network error is retryable

**V1.2 Retry Mechanism**:
- Automatic retry for network errors (connection lost, timeout, etc.)
- Exponential backoff: 1s → 2s → 3s
- Max 3 attempts before failing

**Schema Initialization**:
- **Template Flow** (Recommended): Automatically uses duplicated template databases
  - Finds "Knowledge" and "To-do List" databases via Blocks API
  - No manual setup required
- **Manual Flow**: Creates new databases if template not used
  - Creates workspace-level "S" page
  - Creates "Visual Knowledge" and "Visual Tasks" databases within it

**Atom Types & Routing**:
| Type | Context | Destination | Properties |
|------|---------|-------------|------------|
| `content` | - | Notion Knowledge DB | Name, Description, Note, Category, URL, Captured At |
| `todo` | `work` | Slack Channel | Task, Due Date, Assignee, Description, Note (Block Kit format) |
| `todo` | `life` | Notion Tasks DB | Task, Due Date, Assignee, Status, Description, Note |
| `discard` | - | (ignored) | - |

**V1.2 Enhancements**:
- Added `Note` field for AI-enhanced user notes
- Added `todoContext` field for work/life classification
- Smart routing: work todos → Slack, life todos → Notion

---

### 3. **MorphingHUDView.swift** - Living Orb UI

**Role**: Floating HUD with morphing animation (capture feedback only)

#### Visibility Behavior:
- **Default**: Hidden (not visible on screen)
- **On Capture**: Appears near mouse cursor when three-finger double-tap triggers
- **Capture Window**: 2 seconds where user can hover to add a note
- **Auto-Hide**: Fades out after capture window expires or note is submitted

#### Size States:
| State | Size | Description |
|-------|------|-------------|
| **collapsed** | 60x60 | Living Orb (idle) |
| **compact** | 300x50 | Status display with note count |
| **input** | 320x56+ | Note input mode (V1.2) |

#### Features:
- Hover-based expansion (collapsed → compact, or → input during capture window)
- Capture fly-in animation
- ETL status indicator (已就绪/未配置)
- Report generation button
- Close button
- **V1.2**: User note input with dynamic height (up to 1000 chars)

**V1.2 Change**: Added input mode for user notes during capture window

---

### 3.1 **MainSettingsView.swift** - Unified Settings Window (V1.1)

**Role**: Central settings interface accessible via Dock icon click

#### Tabs:
| Tab | Content |
|-----|--------|
| **账户** | Google OAuth login/logout, user info display |
| **Connectors** | Notion and Slack integration cards with connection status |

#### Window Properties:
- Size: 650x480
- Draggable, closable, minimizable
- Opens on app launch and Dock icon click
- Sidebar navigation with status indicators

**Capture Animation Flow**:
1. Three-finger double-tap detected
2. Panel appears near cursor with fade-in (0.15s)
3. Thumbnail flies from top → orb center (0.4s)
4. Scales down to 20% while moving
5. Impact → thumbnail vanishes
6. Orb flashes green for 1.0s
7. Panel auto-hides with fade-out (0.3s) after 2s total

---

### 4. **InputMonitor.swift** - Gesture Detection

**Role**: Detect three-finger double-tap gesture

**Implementation**:
- **Three-Finger Double-Tap**: MultitouchSupport.framework private API
  - Raw touch count detection
  - Tap duration < 0.3s
  - Double-tap within 0.3s window

---

### 5. **Prompts.swift** - VLM Prompts

**Role**: System prompts for visual analysis

**Key Prompts**:
- `visualNoteAnalysisPrompt()`: Screenshot → {caption, intent}
- `knowledgeReportPrompt()`: Notes → Markdown report
- `screenAnalysisPrompt()`: General screen description
- `visualETLPrompt()`: Screenshot + user note → {type, title, description, category, assignee, due_date, todo_context, user_note}

---

## 🔄 Data Flow

### Visual Note Capture with ETL Pipeline (V1.1)

```
User triggers three-finger double-tap
  ↓
InputMonitor detects → callback
  ↓
KnowledgeBaseService.captureVisualNote()
  ↓
Post .captureEventTriggered notification
  ↓
AppDelegate shows FloatingPanel near cursor (fade-in 0.15s)
  ↓
ScreenCaptureService.captureScreen()
  ↓
Publish CaptureEvent → MorphingHUDView fly-in animation
  ↓
V1.2: Enter Capture Window (2s)
  ↓
[User hovers on panel?]
  - YES → Panel morphs to input mode
    → User types note (max 1000 chars)
    → Press Enter to submit / ESC or mouse leave to cancel
    → onNoteSubmitted callback triggered
  - NO → Capture window expires after 2s
    → Proceed without note
  ↓
KnowledgeBaseService.processCapture(withUserNote:)
  ↓
GeminiLLMService.analyzeImage() → {caption, intent}
  ↓
Store VisualNote (text only, image discarded)
  ↓
Check ETL schema configuration (NotionSchemaState)
  ↓
PipelineController.execute(screenshot:, userNote:)
  ↓
Atomize: VLM extracts structured data + enhances user note → Atom {type, payload, todoContext}
  ↓
Classify atom type and context:
  - content → Save to Notion Knowledge database (with Note field)
  - todo (work context) + Slack connected → Post to Slack channel (Block Kit format)
  - todo (life context) or no Slack → Save to Notion To-do List database (with Note field)
  - discard → Skip (no action)
  ↓
NotionAPIClient or SlackOAuthService creates entry with extracted fields + Note
  ↓
OrbView flashes green (1.0s)
  ↓
Auto-hide FloatingPanel (fade-out 0.3s)
```

### Report Generation

```
User clicks report button / menu item
  ↓
AppState.generateKnowledgeReport()
  ↓
KnowledgeBaseService.generateReportAndCopy()
  ↓
GeminiLLMService with knowledgeReportPrompt()
  ↓
Markdown report → NSPasteboard
  ↓
User pastes report
```

---

## 🎯 Architecture Evolution

### Current Version: Simplified + Notion Integration
- **Added**: Notion OAuth 2.0 authentication
- **Added**: Direct Notion API integration (replaces MCP)
- **Added**: Google OAuth via Supabase
- **Added**: Automatic Notion sync after VLM analysis
- **Added**: Supabase Edge Function for OAuth callback proxy
- **Removed**: Voice input/output (speech recognition, TTS)
- **Removed**: Audio services (AudioManager, HumeService)
- **Removed**: Legacy mechanisms (FactStore, Prerequisite model)
- **Removed**: Deprecated LLM services (QwenLLMService)
- **Removed**: URL processing, TR-P-D flow, step navigation
- **Kept**: Screen capture, VLM analysis, gesture triggers, visual knowledge base

---

## 🔐 Configuration

### Secrets.swift
Contains API keys for:
- Google Gemini API (VLM analysis)
- xAI Grok API (Twitter/X URL analysis)

### SupabaseConfig.swift
- Supabase project URL and anon key
- Google OAuth provider configuration
- Callback URL scheme: `s-navigator://auth/callback`

### NotionOAuthConfig.swift
- Notion OAuth client ID and secret
- Redirect URI: `https://tczeneffgkdxdjyhtrtt.supabase.co/functions/v1/notion-oauth-callback`
- App callback URL: `s-navigator://notion/callback`

### Slack Integration (V1.2)
- Slack OAuth client ID and secret (stored in Edge Function)
- Redirect URI: `https://tczeneffgkdxdjyhtrtt.supabase.co/functions/v1/slack-oauth-callback`
- App callback URL: `s-navigator://slack/callback`
- Scopes: `incoming-webhook`, `chat:write`, `channels:read`
- Tokens stored locally in UserDefaults

### S.entitlements
Required macOS permissions:
- Screen Recording
- Accessibility (for global key monitoring)
- Network (for API calls)

### Info.plist
Custom URL scheme registration:
- `s-navigator://` - Handles OAuth callbacks from Supabase and Notion

---

## 🚀 Key Features Summary

1. **Screen Capture**: Three-finger double-tap gesture
2. **VLM Analysis**: Google Gemini 2.0 Flash for image understanding
3. **Visual Knowledge Base**: Gesture-triggered note capture & synthesis
4. **Notion Integration**: OAuth 2.0 authentication with auto-sync for content and life todos
5. **Slack Integration**: OAuth 2.0 authentication with auto-posting for work todos
6. **Smart Routing**: Work todos → Slack, Life todos & content → Notion
7. **Google OAuth**: User authentication via Supabase
8. **Living Orb UI**: Floating HUD with capture animations and note input
9. **Multi-Monitor Support**: Screen tracking across displays
10. **Retry Mechanism**: Automatic retry for network errors (max 3 attempts)
11. **Direct API Integration**: Notion API and Slack Webhooks for creating entries

---

## 🔌 Notion Integration Architecture

### Overview
Direct Notion API integration with OAuth 2.0 authentication:
1. User authenticates via browser (OAuth 2.0 flow)
2. Access token stored securely in UserDefaults
3. VLM analysis results auto-sync to configured Notion target
4. Supports both pages and databases

### Authentication Flow
```
User clicks "Connect Notion"
    ↓
NotionOAuth2Service.startOAuthFlow()
    ↓
ASWebAuthenticationSession opens browser
    ↓
User chooses authorization option:
    - Use a template (recommended): Duplicates pre-configured S page with databases
    - Select pages: Manual page selection
    ↓
User authorizes in Notion
    ↓
Notion redirects to Supabase Edge Function
    https://.../notion-oauth-callback?code=xxx&duplicated_template_id=xxx (if template chosen)
    ↓
Edge Function redirects to app
    s-navigator://notion/callback?code=xxx
    ↓
AppDelegate receives URL callback
    ↓
NotionOAuth2Service exchanges code for access_token
    ↓
If template chosen:
    - Capture duplicated_template_id from response
    - Wait 0.5s for Notion indexing
    - Use Blocks API to find inline databases (Knowledge, To-do List)
    - Match databases by name (supports "knowledge", "to-do", "todo", "task")
    - Store database IDs in NotionSchemaState
    - If databases not found, create new ones as fallback
    ↓
Token stored in UserDefaults + MCPSettings
    ↓
Connection successful + ETL schema configured
```

### Supabase Edge Functions

#### Notion OAuth Callback
**File**: `supabase/functions/notion-oauth-callback/index.ts`

**Purpose**: OAuth callback proxy (Notion requires https:// redirect URIs)
- Receives authorization code from Notion
- Redirects to app's custom URL scheme
- Enables OAuth flow without requiring a web server

#### Slack OAuth Callback (V1.2)
**File**: `supabase/functions/slack-oauth-callback/index.ts`

**Purpose**: Slack OAuth callback and token exchange
- Receives authorization code from Slack
- Exchanges code for access token and webhook URL
- Passes token data to app via custom URL scheme
- Deployed with `--no-verify-jwt` flag for public access

### Notion API Client
**File**: `Services/Notion/NotionAPIClient.swift`

**Key Methods**:
- `connect()`: Test connection with user info fetch
- `search(query:)`: Search pages and databases
- `createPage()`: Create new page with content
- `createDatabaseEntry()`: Create database entry with properties
- `saveVLMAnalysisResult()`: Save VLM analysis to configured target

### Auto-Sync Flow
```
VLM analysis completes
    ↓
KnowledgeBaseService.saveToNotionIfConfigured()
    ↓
Check: isAuthenticated && hasNotionTarget
    ↓
NotionAPIClient.saveVLMAnalysisResult()
    ↓
Create page/database entry with:
    - Title: "Visual Note - [timestamp]"
    - Content: Caption + Intent + Timestamp
    - Category: Intent classification
    - Confidence: VLM confidence score
    ↓
Return page_id
```

### Settings UI
**AuthSettingsView**: Google OAuth login
- Sign in with Google button
- User info display (email, avatar)
- Sign out option

**NotionSettingsView**: Notion connection & target selection
- Connect/Disconnect Notion button
- Search pages and databases
- Select target for auto-sync
- Display current target (page or database)

---

## 📝 Important Notes

### Critical Dependencies
- **Gemini 2.0 Flash**: Primary VLM (vision + text)
- **MultitouchSupport.framework**: Private API for gesture detection
- **Supabase**: OAuth authentication and Edge Functions
- **Notion API**: Direct API integration for page/database operations

### Performance Considerations
- Image resize for API: max 1024px dimension
- Gesture detection windows: 0.3s for double-tap
- OAuth tokens stored in UserDefaults for session persistence
- Notion API calls are async and non-blocking

### Code Style
- SwiftUI + Combine for reactive state
- @MainActor for UI-bound classes
- Sendable protocols for thread-safe data
- Logging with emoji prefixes (🚀, 📸, 🧠, etc.)

---

## 🎓 Quick Start

Key files to understand:
1. **AppState.swift**: Service orchestration
2. **KnowledgeBaseService.swift**: Visual note capture + Notion sync
3. **PipelineController.swift**: Visual ETL pipeline with retry mechanism
4. **NotionAPIClient.swift**: Direct Notion API integration
5. **NotionOAuth2Service.swift**: Notion OAuth 2.0 authentication flow
6. **SlackOAuthService.swift**: Slack OAuth 2.0 authentication and message posting
7. **MorphingHUDView.swift**: UI with note input mode
8. **FloatingPanelController.swift**: Panel window controller with input activation
9. **CaptureWindowState.swift**: Capture window state management
10. **Atom.swift**: Data model with userNote and todoContext fields
11. **Prompts.swift**: VLM prompts with note enhancement and todo classification
12. **InputMonitor.swift**: Gesture detection
13. **GeminiLLMService.swift**: VLM integration

## 🔧 Setup Instructions

### 1. Configure Supabase
1. Create project at https://supabase.com
2. Enable Google OAuth provider
3. Deploy Edge Functions:
   ```bash
   cd /path/to/S
   supabase functions deploy notion-oauth-callback
   supabase functions deploy slack-oauth-callback --no-verify-jwt
   ```
4. Update `SupabaseConfig.swift` with project URL and anon key

### 2. Configure Notion Integration
1. Create public integration at https://www.notion.so/my-integrations
2. Set redirect URI: `https://[your-project].supabase.co/functions/v1/notion-oauth-callback`
3. (Optional) Configure template page URL for "Use a template" option during OAuth
4. Update `NotionOAuthConfig.swift` with client ID and secret

### 3. Configure Slack Integration (V1.2)
1. Create Slack App at https://api.slack.com/apps
2. Add redirect URI: `https://[your-project].supabase.co/functions/v1/slack-oauth-callback`
3. Enable OAuth scopes: `incoming-webhook`, `chat:write`, `channels:read`
4. Install app to workspace and select default channel
5. Update `SlackOAuthService.swift` with client ID (secret stored in Edge Function)

### 4. First Run
1. Launch app → Grant screen recording permission
2. Click Dock icon → Open Settings
3. **Account Tab**: Sign in with Google
4. **Connectors Tab**:
   - Connect Notion → Authorize in browser → Choose template option (recommended)
   - (Optional) Connect Slack → Authorize in browser → Select channel for work todos
5. Three-finger double-tap to capture → VLM analysis → Smart routing:
   - Content → Notion Knowledge DB
   - Work todos → Slack channel (if connected)
   - Life todos → Notion Tasks DB