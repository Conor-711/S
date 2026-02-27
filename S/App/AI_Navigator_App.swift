import SwiftUI
import AppKit

/// V13: Simplified AI Navigator application
/// Removed: URL processing, step navigation, TR-P-D flow
/// Kept: Screen capture, VLM AI system, gesture triggers
@main
struct AI_Navigator_App: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Application delegate handling window management and lifecycle
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var floatingPanel: FloatingPanelController?
    private var appState: AppState?
    private var screenManager: ScreenManager?
    private var statusItem: NSStatusItem?
    private var hideWorkItem: DispatchWorkItem?
    private var captureWindowWorkItem: DispatchWorkItem?  // V1.2: Capture window timer
    private var captureEventObserver: Any?
    private var mainSettingsWindow: NSWindow?
    
    // V1.2: Shared capture window state
    private let captureWindowState = CaptureWindowState.shared
    private var hasProcessedCurrentCapture: Bool = false  // Prevent double-processing
    
    private func setupCaptureWindowCallbacks() {
        // Cancel timer and activate input mode when user enters input mode
        captureWindowState.onInputModeEntered = { [weak self] in
            self?.captureWindowWorkItem?.cancel()
            self?.floatingPanel?.activateInputMode()
            print("🔮 [AppDelegate] Timer cancelled - user entered input mode, panel activated for input")
        }
        
        // Deactivate input mode when exiting
        captureWindowState.onInputModeExited = { [weak self] in
            self?.floatingPanel?.deactivateInputMode()
            print("🔮 [AppDelegate] Panel input mode deactivated")
        }
    }
    
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupAppState()
            setupFloatingPanel()
            setupScreenManager()
            setupMenuBar()
            setupCaptureWindowCallbacks()
            startSession()
            showMainSettingsWindow()
        }
    }
    
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            appState?.stopSession()
        }
    }
    
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            showMainSettingsWindow()
        }
        return true
    }
    
    // MARK: - URL Handling (OAuth Callback)
    
    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if NotionOAuthService.handleIncomingURL(url) {
                    print("🔐 [AppDelegate] Handled OAuth callback URL")
                }
            }
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupAppState() {
        appState = AppState()
    }
    
    private func setupFloatingPanel() {
        guard let appState = appState else { return }
        
        floatingPanel = FloatingPanelController {
            EmptyView()
        }
        
        let onClose: () -> Void = { [weak self, weak appState] in
            appState?.resetSession()
            self?.hidePanel()
        }
        
        let onGenerateReport: () async -> Void = { [weak appState] in
            do {
                try await appState?.knowledgeBaseService.generateReportAndCopy()
                print("📋 [AppDelegate] Knowledge report copied to clipboard!")
            } catch {
                print("❌ [AppDelegate] Failed to generate report: \(error)")
            }
        }
        
        // V1.2: Note submission callback
        let onNoteSubmitted: (String?) -> Void = { [weak self, weak appState] note in
            Task { @MainActor in
                self?.handleNoteSubmitted(note: note, appState: appState)
            }
        }
        
        // V14: MorphingHUDView with ConnectorService for MCP
        // V1.2: Added onNoteSubmitted callback and shared captureWindowState
        let morphingHUDView = MorphingHUDView(
            knowledgeBaseService: appState.knowledgeBaseService,
            captureWindowState: captureWindowState,
            connectorService: appState.connectorService,
            onClose: onClose,
            onGenerateReport: onGenerateReport,
            onNoteSubmitted: onNoteSubmitted
        )
        
        floatingPanel?.updateContent {
            morphingHUDView
        }
        
        // Panel starts hidden - will show on capture trigger
        floatingPanel?.orderOut(nil)
        
        // Observe capture events to show/hide panel
        setupCaptureEventObserver()
    }
    
    private func setupCaptureEventObserver() {
        // Observe capture events from KnowledgeBaseService
        captureEventObserver = NotificationCenter.default.addObserver(
            forName: .captureEventTriggered,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showPanelNearCursor()
            }
        }
        
        print("👁️ [AppDelegate] Capture event observer setup complete")
    }
    
    /// Show panel near cursor with auto-hide after animation
    /// V1.2: Now enters capture window mode for potential note input
    private func showPanelNearCursor() {
        // Cancel any pending hide and capture window
        hideWorkItem?.cancel()
        captureWindowWorkItem?.cancel()
        
        // Position near cursor and show with animation
        floatingPanel?.positionNearCursor(offset: 30)
        floatingPanel?.showWithAnimation(duration: 0.15)
        
        // V1.2: Enter capture window mode using shared state
        captureWindowState.enterCaptureWindow()
        hasProcessedCurrentCapture = false  // Reset for new capture
        
        print("🔮 [AppDelegate] Panel shown near cursor (capture window active)")
        
        // V1.2: Schedule capture window expiration (2s)
        // After 2s, if user hasn't hovered to input, auto-hide and proceed with AI flow
        let captureWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Only expire if not in input mode
            guard self.captureWindowState.shouldTimerExpire() else {
                print("🔮 [AppDelegate] Timer fired but user is in input mode, ignoring")
                return
            }
            
            // Exit capture window without note
            self.captureWindowState.exitCaptureWindow()
            
            // Proceed with AI flow (no note)
            self.proceedWithAIFlow(userNote: nil)
            
            // Hide panel
            self.floatingPanel?.hideWithAnimation(duration: 0.3)
            print("🔮 [AppDelegate] Capture window expired, proceeding without note")
        }
        captureWindowWorkItem = captureWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: captureWorkItem)
    }
    
    // MARK: - V1.2: Note Handling
    
    /// Handle note submission from MorphingHUDView
    private func handleNoteSubmitted(note: String?, appState: AppState?) {
        // Cancel capture window timer
        captureWindowWorkItem?.cancel()
        
        print("📝 [AppDelegate] Note =received: \(note ?? "(none)")")
        
        // Proceed with AI flow with the note
        proceedWithAIFlow(userNote: note)
        
        // Hide panel
        floatingPanel?.hideWithAnimation(duration: 0.3)
    }
    
    /// Proceed with AI analysis flow
    private func proceedWithAIFlow(userNote: String?) {
        // Prevent double-processing
        guard !hasProcessedCurrentCapture else {
            print("🔮 [AppDelegate] Already processed this capture, skipping")
            return
        }
        hasProcessedCurrentCapture = true
        
        guard let appState = appState else { return }
        
        // Call knowledge base service with the user note
        Task {
            await appState.knowledgeBaseService.processCapture(withUserNote: userNote)
        }
    }
    
    private func setupScreenManager() {
        guard let appState = appState else { return }
        
        screenManager = ScreenManager()
        screenManager?.configure(
            floatingPanel: floatingPanel,
            screenCaptureService: appState.captureService
        )
        screenManager?.startTracking()
    }
    
    private func startSession() {
        appState?.startSession()
    }
    
    // MARK: - Public Methods
    
    func showPanel() {
        floatingPanel?.showWithoutFocus()
    }
    
    func hidePanel() {
        floatingPanel?.orderOut(nil)
    }
    
    func togglePanel() {
        if floatingPanel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Navigator")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        // Show/Hide Panel
        let toggleItem = NSMenuItem(title: "Toggle Panel", action: #selector(togglePanelAction), keyEquivalent: "n")
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Knowledge Base
        let captureNoteItem = NSMenuItem(title: "Capture Visual Note", action: #selector(captureVisualNoteAction), keyEquivalent: "")
        captureNoteItem.target = self
        menu.addItem(captureNoteItem)
        
        let generateReportItem = NSMenuItem(title: "Generate Knowledge Report", action: #selector(generateReportAction), keyEquivalent: "")
        generateReportItem.target = self
        menu.addItem(generateReportItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit S", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        
        print("📱 [AppDelegate] Menu bar setup complete")
    }
    
    // MARK: - Menu Actions
    
    @objc private func togglePanelAction() {
        togglePanel()
    }
    
    @objc private func captureVisualNoteAction() {
        appState?.captureVisualNote()
    }
    
    @objc private func generateReportAction() {
        appState?.generateKnowledgeReport()
    }
    
    @objc private func checkForUpdatesAction() {
        #if canImport(Sparkle)
        SparkleUpdaterController.shared.checkForUpdates()
        #else
        print("⚠️ [AppDelegate] Sparkle not available for updates")
        #endif
    }
    
    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Main Settings Window
    
    private func showMainSettingsWindow() {
        guard let appState = appState else { return }
        
        // If window exists and is visible, just bring to front
        if let window = mainSettingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let settingsView = MainSettingsView(connectorService: appState.connectorService)
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "S - Collection"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 1100, height: 780))
        window.center()
        window.isReleasedWhenClosed = false
        
        mainSettingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("🔧 [AppDelegate] Main settings window opened")
    }
    
    @objc private func openSettingsAction() {
        showMainSettingsWindow()
    }
}
