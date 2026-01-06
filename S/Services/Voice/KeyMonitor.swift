import Foundation
import AppKit
import Combine

/// Global key monitor for fn key push-to-talk functionality
/// Listens globally (even when app is backgrounded) for fn key press/release
@MainActor
final class GlobalKeyMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isFnKeyPressed: Bool = false
    
    // MARK: - Private Properties
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressStartTime: Date?
    private let debounceThreshold: TimeInterval = 0.2
    
    // MARK: - Callbacks
    
    var onRecordingStart: (() -> Void)?
    var onRecordingEnd: ((Bool) -> Void)?  // Bool indicates if should process (not debounced)
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        Task { @MainActor in
            stopMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for global fn key events
    func startMonitoring() {
        guard globalMonitor == nil else {
            print("🔑 [GlobalKeyMonitor] Already monitoring")
            return
        }
        
        // Global monitor for when app is in background
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        // Local monitor for when app is in foreground
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
        
        print("🔑 [GlobalKeyMonitor] Started monitoring fn key")
    }
    
    /// Stop monitoring for key events
    func stopMonitoring() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        
        print("🔑 [GlobalKeyMonitor] Stopped monitoring")
    }
    
    // MARK: - Private Methods
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let optionPressed = event.modifierFlags.contains(.option)
        
        // Detect option key state change
        if optionPressed && !isFnKeyPressed {
            // option key pressed
            onOptionKeyPressed()
        } else if !optionPressed && isFnKeyPressed {
            // option key released
            onOptionKeyReleased()
        }
    }
    
    private func onOptionKeyPressed() {
        isFnKeyPressed = true
        pressStartTime = Date()
        
        print("🔑 [GlobalKeyMonitor] option key pressed")
        onRecordingStart?()
    }
    
    private func onOptionKeyReleased() {
        isFnKeyPressed = false
        
        // Calculate press duration for debounce
        let duration: TimeInterval
        if let startTime = pressStartTime {
            duration = Date().timeIntervalSince(startTime)
        } else {
            duration = 0
        }
        
        pressStartTime = nil
        
        let shouldProcess = duration >= debounceThreshold
        
        if shouldProcess {
            print("🔑 [GlobalKeyMonitor] option key released after \(String(format: "%.2f", duration))s - processing")
        } else {
            print("🔑 [GlobalKeyMonitor] option key released after \(String(format: "%.2f", duration))s - debounced (too short)")
        }
        
        onRecordingEnd?(shouldProcess)
    }
}
