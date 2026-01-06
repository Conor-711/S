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
        // V10: Use borderless + fullSizeContentView to eliminate any frame/border area
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true  // Defer creation to allow configuration before display
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
        // V10: Refactored for true transparency (no gray border)
        
        // CRITICAL: Set appearance to nil to avoid system styling
        appearance = nil
        
        // 1. Window level and behavior
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        
        // 2. TitleBar: Explicit transparent and hidden
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        // 3. Backing: Transparent background - USE RGBA COLOR SPACE (not grayscale)
        isOpaque = false
        backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        // 4. Shadow: Disabled (SwiftUI handles its own shadow)
        hasShadow = false
        
        // 5. Additional settings
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }
    
    private func setupContentView<Content: View>(_ content: Content) {
        // V10: Wrap content with transparent background
        let wrappedContent = AnyView(
            content
                .ignoresSafeArea()
                .background(Color.clear)
        )
        
        // V10: SOLUTION - Direct hosting view with proper configuration
        // Create hosting view directly - avoid extra wrapper layers
        let hosting = TransparentHostingView(rootView: wrappedContent)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        
        // Store reference
        self.hostingView = hosting
        
        // Directly assign hosting view as contentView
        contentView = hosting
        
        // V10: CRITICAL - Clear window's backing view layer (contentView.superview)
        clearWindowBackingLayer()
        
        // V10: Deferred transparency
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.clearWindowBackingLayer()
            self?.makeAllLayersTransparent()
        }
    }
    
    /// V10: CRITICAL - Clear the window's backing view layer (the actual source of gray border)
    private func clearWindowBackingLayer() {
        // Clear ALL views in the window hierarchy
        // Start from contentView and go up to find NSThemeFrame
        var currentView: NSView? = contentView
        while let view = currentView {
            view.wantsLayer = true
            view.layer?.backgroundColor = nil
            view.layer?.isOpaque = false
            
            // Also clear the view's draw background if it has one
            if let layer = view.layer {
                layer.sublayers?.forEach { sublayer in
                    sublayer.backgroundColor = nil
                    sublayer.isOpaque = false
                }
            }
            
            currentView = view.superview
        }
        
        // Also ensure contentView layer is transparent
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = nil
        contentView?.layer?.isOpaque = false
        
        // Force display update
        contentView?.superview?.needsDisplay = true
    }
    
    /// V10: Recursively clear all layer backgrounds
    private func makeAllLayersTransparent() {
        guard let cv = contentView else { return }
        
        // Clear contentView and its layers
        clearLayerBackgrounds(cv.layer)
        clearSubviewBackgrounds(cv)
        
        // Also clear superview (window backing layer)
        if let superview = cv.superview {
            clearLayerBackgrounds(superview.layer)
        }
    }
    
    private func clearLayerBackgrounds(_ layer: CALayer?) {
        guard let layer = layer else { return }
        layer.backgroundColor = nil
        layer.isOpaque = false
        
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                clearLayerBackgrounds(sublayer)
            }
        }
    }
    
    private func clearSubviewBackgrounds(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = nil
        view.layer?.isOpaque = false
        
        for subview in view.subviews {
            clearSubviewBackgrounds(subview)
        }
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
        
        // V10: Removed minimum size constraints to allow orb (60x60) to display without border
        let maxHeight: CGFloat = 500
        
        let newWidth = targetSize.width
        let newHeight = min(targetSize.height, maxHeight)
        
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
        case .bottomCenter:
            // V10: Center horizontally at bottom
            newOrigin = NSPoint(
                x: screenFrame.midX - panelFrame.width / 2,
                y: screenFrame.minY + padding
            )
        }
        
        setFrameOrigin(newOrigin)
    }
    
    // V10: Position for Living Orb with dynamic width
    func positionForOrb(padding: CGFloat = 20) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Position at bottom center, accounting for orb size (60pt)
        let orbSize: CGFloat = 60
        let newOrigin = NSPoint(
            x: screenFrame.midX - orbSize / 2,
            y: screenFrame.minY + padding
        )
        
        setFrameOrigin(newOrigin)
    }
    
    /// Position the panel near the current mouse cursor
    func positionNearCursor(offset: CGFloat = 50) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        let orbSize: CGFloat = 60
        
        // Position slightly below and to the right of cursor
        var newX = mouseLocation.x + offset
        var newY = mouseLocation.y - offset - orbSize
        
        // Ensure panel stays within screen bounds
        if newX + panelFrame.width > screenFrame.maxX {
            newX = mouseLocation.x - offset - orbSize
        }
        if newX < screenFrame.minX {
            newX = screenFrame.minX + 20
        }
        if newY < screenFrame.minY {
            newY = screenFrame.minY + 20
        }
        if newY + panelFrame.height > screenFrame.maxY {
            newY = screenFrame.maxY - panelFrame.height - 20
        }
        
        setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    /// Show the panel with fade-in animation
    func showWithAnimation(duration: TimeInterval = 0.2) {
        alphaValue = 0
        orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }
    
    /// Hide the panel with fade-out animation
    func hideWithAnimation(duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}

// MARK: - V10: Transparent Background View (Solution B)

/// Custom NSView that overrides draw() to actively draw clear color
/// This is the KEY fix - it overrides NSThemeFrame's default gray drawing
class TransparentBackgroundView: NSView {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTransparency()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTransparency()
    }
    
    private func setupTransparency() {
        wantsLayer = true
        layer?.backgroundColor = nil
        layer?.isOpaque = false
    }
    
    /// CRITICAL: Override draw() to actively draw transparent color
    /// This overrides the system's default gray background drawing
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }
    
    override var isOpaque: Bool {
        return false
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Also clear superview's layer (NSThemeFrame)
        superview?.wantsLayer = true
        superview?.layer?.backgroundColor = nil
        superview?.layer?.isOpaque = false
        
        // Force redraw
        needsDisplay = true
    }
}

// MARK: - V10: Transparent Hosting View

/// Custom NSHostingView subclass that ensures complete transparency
class TransparentHostingView<Content: View>: NSHostingView<Content> {
    
    required init(rootView: Content) {
        super.init(rootView: rootView)
        setupTransparency()
    }
    
    @MainActor required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTransparency()
    }
    
    private func setupTransparency() {
        wantsLayer = true
        layer?.backgroundColor = nil
        layer?.isOpaque = false
    }
    
    /// CRITICAL: Override draw() to draw nothing (let SwiftUI handle it)
    override func draw(_ dirtyRect: NSRect) {
        // Don't call super - let SwiftUI content draw itself
        // Draw clear background first
        NSColor.clear.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
    
    override var isOpaque: Bool {
        return false
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTransparency()
        
        // Clear superview's layer
        superview?.wantsLayer = true
        superview?.layer?.backgroundColor = nil
        superview?.layer?.isOpaque = false
    }
    
    override func layout() {
        super.layout()
        layer?.backgroundColor = nil
        layer?.isOpaque = false
    }
}

// MARK: - Panel Corner Enum

enum PanelCorner {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
    case bottomCenter  // V10: Living Orb default position
}

// MARK: - KeyableFloatingPanel

/// Alternative panel that can become key when needed
final class KeyableFloatingPanel: NSPanel {
    
    private var allowsKeyStatus: Bool = false
    
    init<Content: View>(contentRect: NSRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
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
