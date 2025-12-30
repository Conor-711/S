import SwiftUI
import AppKit

/// Main entry point for the AI Navigator application
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
    
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupAppState()
            setupFloatingPanel()
            startSession()
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
    
    // MARK: - Setup Methods
    
    private func setupAppState() {
        appState = AppState()
    }
    
    private func setupFloatingPanel() {
        guard let appState = appState else { return }
        
        var hudView = HUDView(
            viewModel: appState.hudViewModel,
            agentController: appState.agentController
        )
        
        // Set up callback for starting agent
        hudView.onStartAgent = { [weak appState] goal in
            appState?.startAgent(goal: goal)
        }
        
        // Set up callback for requesting next step
        hudView.onRequestNextStep = { [weak appState] in
            appState?.requestNextStep()
        }
        
        // Set up callback for close button (Phase 4)
        hudView.onClose = { [weak appState, weak self] in
            appState?.resetSession()
            self?.floatingPanel?.orderOut(nil)
        }
        
        floatingPanel = FloatingPanelController {
            hudView
        }
        
        appState.hudViewModel.onActivateInputMode = { [weak self] in
            self?.floatingPanel?.activateInputMode()
        }
        
        appState.hudViewModel.onDeactivateInputMode = { [weak self] in
            self?.floatingPanel?.deactivateInputMode()
        }
        
        // Phase 4: Set up screen change handler for multi-monitor
        appState.screenManager.onScreenChanged = { [weak self, weak appState] screen, displayID in
            guard let self = self, let appState = appState else { return }
            
            // Move panel to bottom of new screen
            self.movePanel(to: screen)
            
            // Update capture target
            appState.captureService.updateTargetScreen(displayID: displayID)
        }
        
        floatingPanel?.positionAt(corner: .topRight, padding: 20)
        floatingPanel?.showWithoutFocus()
    }
    
    /// Move panel to bottom center of specified screen
    private func movePanel(to screen: NSScreen) {
        guard let panel = floatingPanel else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        
        let newX = screenFrame.midX - (panelFrame.width / 2)
        let newY = screenFrame.minY + 20  // 20pt from bottom
        
        let newFrame = NSRect(x: newX, y: newY, width: panelFrame.width, height: panelFrame.height)
        
        panel.setFrame(newFrame, display: true, animate: true)
        print("🖥️ [AppDelegate] Moved panel to screen at \(newX), \(newY)")
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
}
