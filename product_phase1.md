🏗️ Phase 1 Scaffolding Instructions: macOS AI Navigator

Project Context:
We are building a macOS-native Human-in-the-Loop AI Agent.
The app watches the user's screen (via ScreenCaptureKit), uses VLM (Qwen-VL-Plus) to analyze the state, and guides the user through complex software tasks via a floating HUD panel.

Tech Stack:

OS: macOS 13.0+ (Ventura)

Language: Swift 6 (Strict Concurrency)

UI: SwiftUI + AppKit (NSPanel for floating window)

AI Backend: Alibaba DashScope API (qwen-vl-plus for vision, qwen-max for planning)

Core Frameworks: ScreenCaptureKit, Combine

🛑 Step 1: Project Structure (The Skeleton)

Please create the following folder structure in the Xcode project. If files do not exist, create them.

code
Text
download
content_copy
expand_less
AI_Navigator_MVP/
├── App/
│   ├── AI_Navigator_App.swift      // Entry point
│   ├── AppState.swift              // Global State Manager (ObservableObject)
├── Config/
│   ├── Secrets.swift               // Hardcoded API Keys (Model: Qwen)
├── Models/
│   ├── TaskStep.swift              // Struct for navigation steps
│   ├── SessionContext.swift        // Struct for execution history
├── Services/
│   ├── Network/
│   │   ├── LLMServiceProtocol.swift
│   │   ├── QwenLLMService.swift    // Implementation with Retry Logic
│   ├── Capture/
│   │   ├── ScreenCaptureService.swift // ScreenCaptureKit implementation
│   │   ├── ImageDiffer.swift       // Strict Pixel Equality Check
├── ViewModels/
│   ├── HUDViewModel.swift          // Logic for the Floating Panel
├── Views/
│   ├── FloatingPanel/
│   │   ├── FloatingPanelController.swift // NSPanel Logic (HUD Mode)
│   │   ├── HUDView.swift           // SwiftUI Content
🛑 Step 2: Implementation Details (The Stubs)

Please generate the code for the files above following these Specific Constraints:

1. Configuration (Secrets.swift)

Create a static struct to hold the API Key.

Variable: static let qwenAPIKey = "YOUR_DASHSCOPE_KEY_HERE"

Note: Add a comment reminding to replace this.

2. Screen Capture & Diffing (ScreenCaptureService.swift & ImageDiffer.swift)

Framework: Use ScreenCaptureKit (SCScreenshotManager or SCStream).

Logic:

Implement a startPolling(interval: TimeInterval) method.

Critical: Before emitting a new screenshot, compare it with the previous one.

Diffing Strategy: Pixel-level Strict Equality. Convert NSImage -> Data (TIFF or PNG representation) and check currentData == oldData. If they are identical, drop the frame and do not notify listeners. Only emit when data changes.

3. Network Layer (QwenLLMService.swift)

Models:

qwen-vl-plus for image analysis.

qwen-max for text planning.

Retry Logic (Strategy A):

Implement a mechanism to automatically retry failed requests 3 times.

If it fails 3 times, print("Error: Network request failed") to the console.

Do not propagate the error to the UI (UI remains unaware/silent).

4. Floating Window Logic (FloatingPanelController.swift)

Subclass: NSPanel.

Style:

.nonactivatingPanel (Does not take focus on click by default).

.hudWindow (Optional, but needs transparency).

Level: .floating (Always on top).

CollectionBehavior: .canJoinAllSpaces, .fullScreenAuxiliary.

Focus Management (Mode A):

The window should generally not accept key focus (to allow user to type in browser).

Provide a method activateInputMode() which calls NSApp.activate(ignoringOtherApps: true) and self.makeKeyAndOrderFront(nil) ONLY when specific UI buttons are clicked (e.g., an "Input" button).

5. Global State (AppState.swift)

Create an @Observable class (or ObservableObject).

Properties:

currentImage: NSImage?

currentInstruction: String

isProcessing: Bool

Methods:

startSession(): Boots up the Capture Service.

🛑 Step 3: Wiring It Up

In AI_Navigator_App.swift:

Initialize AppState.

Initialize FloatingPanelController with HUDView as root view.

Ensure the panel shows up on launch without stealing focus.

Action:
Please generate the code for these files now. Start with the Protocols and Models, then the Services, and finally the UI.