import AppKit
import SwiftUI
import Combine

/// Custom NSPanel for the floating HUD window
/// Configured to float above all windows without stealing focus
final class FloatingPanelController: NSPanel {
    
    /// Controls whether the panel can become key window
    private var allowsKeyStatus: Bool = false
    
    /// Hosting view for SwiftUI content
    private var hostingView: NSHostingView<AnyView>?
    
    /// Observer for content size changes
    private var sizeObserver: NSKeyValueObservation?
    
    // MARK: - Initialization
    
    init<Content: View>(contentRect: NSRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        configurePanel()
        setupContentView(content())
        setupSizeObserver()
    }
    
    /// Convenience initializer with default size
    convenience init<Content: View>(@ViewBuilder content: () -> Content) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 400, height: 300)
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 150
        
        let xPosition = screenFrame.maxX - panelWidth - 20
        let yPosition = screenFrame.maxY - panelHeight - 20
        
        let contentRect = NSRect(x: xPosition, y: yPosition, width: panelWidth, height: panelHeight)
        
        self.init(contentRect: contentRect, content: content)
    }
    
    deinit {
        sizeObserver?.invalidate()
    }
    
    // MARK: - Configuration
    
    private func configurePanel() {
        level = .floating
        
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        
        // Phase 3: Enable drag by window background
        isMovableByWindowBackground = true
        
        backgroundColor = NSColor.clear
        isOpaque = false
        
        // Phase 3: Enable shadow for better visibility
        hasShadow = true
        
        animationBehavior = .utilityWindow
        
        // Phase 3: Additional shadow configuration
        invalidateShadow()
    }
    
    private func setupContentView<Content: View>(_ content: Content) {
        let wrappedContent = AnyView(content)
        let hosting = NSHostingView(rootView: wrappedContent)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        
        self.hostingView = hosting
        contentView = hosting
    }
    
    // MARK: - Phase 3: Auto-Resize Support
    
    private func setupSizeObserver() {
        guard let hostingView = hostingView else { return }
        
        sizeObserver = hostingView.observe(\.fittingSize, options: [.new]) { [weak self] view, change in
            guard let self = self, let newSize = change.newValue else { return }
            self.animateToFitContent(newSize)
        }
    }
    
    /// Animate the window frame to fit the content size
    func animateToFitContent(_ contentSize: CGSize? = nil) {
        let targetSize: CGSize
        
        if let size = contentSize {
            targetSize = size
        } else if let hostingView = hostingView {
            targetSize = hostingView.fittingSize
        } else {
            return
        }
        
        // Ensure minimum size
        let minWidth: CGFloat = 320
        let minHeight: CGFloat = 80
        let maxHeight: CGFloat = 400
        
        let newWidth = max(targetSize.width, minWidth)
        let newHeight = min(max(targetSize.height, minHeight), maxHeight)
        
        // Calculate new frame, keeping top-right anchor
        var newFrame = frame
        let heightDiff = newHeight - frame.height
        newFrame.size.width = newWidth
        newFrame.size.height = newHeight
        newFrame.origin.y -= heightDiff  // Adjust Y to keep top anchored
        
        // Animate the frame change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }
    
    /// Force refresh content size
    func refreshContentSize() {
        DispatchQueue.main.async { [weak self] in
            self?.animateToFitContent()
        }
    }
    
    // MARK: - Focus Management (Mode A)
    
    /// Override to dynamically control key window status
    override var canBecomeKey: Bool {
        return allowsKeyStatus
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    /// Activate input mode - allows the panel to receive keyboard input
    /// Call this when specific UI buttons are clicked (e.g., "Input" button)
    func activateInputMode() {
        allowsKeyStatus = true
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
    
    /// Deactivate input mode - returns to non-activating state
    func deactivateInputMode() {
        allowsKeyStatus = false
        resignKey()
        orderFront(nil)
    }
    
    // MARK: - Public Methods
    
    /// Show the panel without stealing focus
    func showWithoutFocus() {
        orderFrontRegardless()
    }
    
    /// Update the panel's SwiftUI content
    func updateContent<Content: View>(@ViewBuilder content: () -> Content) {
        setupContentView(content())
    }
    
    /// Position the panel at a specific corner of the screen
    func positionAt(corner: PanelCorner, padding: CGFloat = 20) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        var newOrigin: NSPoint
        
        switch corner {
        case .topRight:
            newOrigin = NSPoint(
                x: screenFrame.maxX - panelFrame.width - padding,
                y: screenFrame.maxY - panelFrame.height - padding
            )
        case .topLeft:
            newOrigin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - panelFrame.height - padding
            )
        case .bottomRight:
            newOrigin = NSPoint(
                x: screenFrame.maxX - panelFrame.width - padding,
                y: screenFrame.minY + padding
            )
        case .bottomLeft:
            newOrigin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        }
        
        setFrameOrigin(newOrigin)
    }
}

// MARK: - Panel Corner Enum

enum PanelCorner {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
}

// MARK: - KeyableFloatingPanel

/// Alternative panel that can become key when needed
final class KeyableFloatingPanel: NSPanel {
    
    private var allowsKeyStatus: Bool = false
    
    init<Content: View>(contentRect: NSRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        configurePanel()
        
        let hostingView = NSHostingView(rootView: content())
        contentView = hostingView
    }
    
    private func configurePanel() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = NSColor.clear
        isOpaque = false
        hasShadow = true
    }
    
    override var canBecomeKey: Bool {
        return allowsKeyStatus
    }
    
    func activateInputMode() {
        allowsKeyStatus = true
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
    
    func deactivateInputMode() {
        allowsKeyStatus = false
        resignKey()
        orderFront(nil)
    }
}
