import Foundation
import AppKit
import Combine

/// Service for managing multi-monitor support and following mouse cursor
/// Phase 4: Tracks mouse position and moves panel/capture to active screen
@MainActor
final class ScreenManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentScreen: NSScreen?
    @Published private(set) var currentDisplayID: CGDirectDisplayID?
    
    // MARK: - Dependencies
    
    private weak var floatingPanel: NSPanel?
    private weak var screenCaptureService: ScreenCaptureService?
    
    // MARK: - Private Properties
    
    private var mouseMonitor: Any?
    private var pollingTimer: Timer?
    private let panelOffset: CGFloat = 20
    
    // MARK: - Initialization
    
    init() {
        currentScreen = NSScreen.main
        currentDisplayID = currentScreen?.displayID
    }
    
    deinit {
        // Remove mouse monitor synchronously (no actor isolation needed)
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        pollingTimer?.invalidate()
    }
    
    // MARK: - Configuration
    
    /// Configure the screen manager with dependencies
    func configure(floatingPanel: NSPanel?, screenCaptureService: ScreenCaptureService?) {
        self.floatingPanel = floatingPanel
        self.screenCaptureService = screenCaptureService
    }
    
    // MARK: - Tracking
    
    /// Start tracking mouse position for screen changes
    func startTracking() {
        guard mouseMonitor == nil else { return }
        
        print("🖥️ [ScreenManager] Starting mouse tracking")
        
        // Use global mouse moved monitor
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMoved()
            }
        }
        
        // Also use polling as fallback (every 2 seconds)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMouseMoved()
            }
        }
        
        // Initial check
        handleMouseMoved()
    }
    
    /// Stop tracking mouse position
    func stopTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        pollingTimer?.invalidate()
        pollingTimer = nil
        print("🖥️ [ScreenManager] Stopped mouse tracking")
    }
    
    // MARK: - Screen Detection
    
    /// Handle mouse movement and detect screen changes
    private func handleMouseMoved() {
        let mouseLocation = NSEvent.mouseLocation
        
        // Find which screen contains the mouse
        guard let newScreen = screenContaining(point: mouseLocation) else { return }
        
        // Check if screen changed
        let newDisplayID = newScreen.displayID
        if newDisplayID != currentDisplayID {
            print("🖥️ [ScreenManager] Screen changed from \(currentDisplayID ?? 0) to \(newDisplayID)")
            currentScreen = newScreen
            currentDisplayID = newDisplayID
            
            // Move panel to new screen
            movePanelToScreen(newScreen)
            
            // Update capture service target
            screenCaptureService?.updateTargetScreen(displayID: newDisplayID)
        }
    }
    
    /// Find the screen containing a point
    private func screenContaining(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.main
    }
    
    // MARK: - Panel Movement
    
    /// Move the floating panel to a new screen (bottom position)
    private func movePanelToScreen(_ screen: NSScreen) {
        guard let panel = floatingPanel else { return }
        
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        
        // Position at bottom center of the screen
        let newOrigin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + panelOffset
        )
        
        // Animate the move
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(newOrigin)
        }
        
        print("🖥️ [ScreenManager] Moved panel to screen at (\(Int(newOrigin.x)), \(Int(newOrigin.y)))")
    }
    
    /// Manually move panel to a specific corner on current screen
    func movePanelToCorner(_ corner: PanelCorner) {
        guard let panel = floatingPanel, let screen = currentScreen else { return }
        
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        
        var newOrigin: NSPoint
        
        switch corner {
        case .topRight:
            newOrigin = NSPoint(
                x: screenFrame.maxX - panelSize.width - panelOffset,
                y: screenFrame.maxY - panelSize.height - panelOffset
            )
        case .topLeft:
            newOrigin = NSPoint(
                x: screenFrame.minX + panelOffset,
                y: screenFrame.maxY - panelSize.height - panelOffset
            )
        case .bottomRight:
            newOrigin = NSPoint(
                x: screenFrame.maxX - panelSize.width - panelOffset,
                y: screenFrame.minY + panelOffset
            )
        case .bottomLeft:
            newOrigin = NSPoint(
                x: screenFrame.minX + panelOffset,
                y: screenFrame.minY + panelOffset
            )
        case .bottomCenter:
            // V10: Center horizontally at bottom
            newOrigin = NSPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.minY + panelOffset
            )
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(newOrigin)
        }
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    /// Get the CGDirectDisplayID for this screen
    var displayID: CGDirectDisplayID {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
