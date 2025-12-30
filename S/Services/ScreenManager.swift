import Foundation
import AppKit
import Combine

/// Service for tracking mouse position and managing multi-monitor support
@MainActor
final class ScreenManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentScreen: NSScreen?
    @Published private(set) var currentDisplayID: CGDirectDisplayID?
    
    // MARK: - Private Properties
    
    private var mouseMonitor: Any?
    private var pollingTimer: Timer?
    private var lastScreenFrame: NSRect?
    
    // MARK: - Callbacks
    
    var onScreenChanged: ((NSScreen, CGDirectDisplayID) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        currentScreen = NSScreen.main
        currentDisplayID = currentScreen?.displayID
    }
    
    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        pollingTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking mouse position to detect screen changes
    func startTracking() {
        // Try global monitor first
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.checkMouseScreen()
            }
        }
        
        // Also use polling as backup (for when global monitor doesn't fire)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkMouseScreen()
            }
        }
        
        // Initial check
        checkMouseScreen()
        
        print("🖥️ [ScreenManager] Started tracking mouse position")
    }
    
    /// Stop tracking mouse position
    func stopTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        print("🖥️ [ScreenManager] Stopped tracking")
    }
    
    /// Get the display ID for a given screen
    func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        return screen.displayID
    }
    
    /// Get all available screens
    var allScreens: [NSScreen] {
        return NSScreen.screens
    }
    
    // MARK: - Private Methods
    
    private func checkMouseScreen() {
        let mouseLocation = NSEvent.mouseLocation
        
        // Find which screen contains the mouse
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                // Check if screen changed
                if screen.frame != lastScreenFrame {
                    lastScreenFrame = screen.frame
                    currentScreen = screen
                    
                    if let displayID = screen.displayID {
                        currentDisplayID = displayID
                        print("🖥️ [ScreenManager] Screen changed to display \(displayID)")
                        onScreenChanged?(screen, displayID)
                    }
                }
                break
            }
        }
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    /// Get the CGDirectDisplayID for this screen
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
