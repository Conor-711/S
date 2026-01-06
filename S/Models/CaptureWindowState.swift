import Foundation

// MARK: - V1.2 Capture Window State
// Observable state for sharing capture window mode between AppDelegate and MorphingHUDView

@MainActor
final class CaptureWindowState: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CaptureWindowState()
    
    // MARK: - Published State
    
    /// Whether we're in the 2-second capture window where user can add a note
    @Published var isInCaptureWindow: Bool = false
    
    /// Whether user is actively in input mode (typing a note)
    @Published var isInInputMode: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when user enters input mode - used to cancel the 2s timer
    var onInputModeEntered: (() -> Void)?
    
    /// Called when input mode exits - used to deactivate panel input
    var onInputModeExited: (() -> Void)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Enter capture window mode (called when capture is triggered)
    func enterCaptureWindow() {
        isInCaptureWindow = true
        isInInputMode = false
        print("📝 [CaptureWindowState] Entered capture window")
    }
    
    /// Enter input mode (called when user hovers and panel transforms to input)
    func enterInputMode() {
        guard isInCaptureWindow else { return }
        isInInputMode = true
        onInputModeEntered?()
        print("📝 [CaptureWindowState] Entered input mode")
    }
    
    /// Exit capture window mode (called when window expires or note is submitted)
    func exitCaptureWindow() {
        let wasInInputMode = isInInputMode
        isInCaptureWindow = false
        isInInputMode = false
        
        // Notify to deactivate panel input if was in input mode
        if wasInInputMode {
            onInputModeExited?()
        }
        print("📝 [CaptureWindowState] Exited capture window")
    }
    
    /// Check if timer should expire (only if not in input mode)
    func shouldTimerExpire() -> Bool {
        return isInCaptureWindow && !isInInputMode
    }
}
