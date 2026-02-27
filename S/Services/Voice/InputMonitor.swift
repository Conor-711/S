import Foundation
import AppKit
import Combine

// MARK: - Multitouch Private API Bridge

// Global callback for multitouch - must be at file scope for @convention(c)
private var globalTouchCountCallback: ((Int) -> Void)?
private var callbackInvokeCount = 0

// MTTouch struct layout (from reverse engineering)
// Total size: 48 bytes on modern macOS
private struct MTTouchData {
    var frame: Int32           // 0
    var timestamp: Double      // 4
    var identifier: Int32      // 12
    var state: Int32           // 16 - THIS IS WHAT WE NEED (4 = touching)
    var fingerId: Int32        // 20
    var handId: Int32          // 24
    var normalizedX: Float     // 28
    var normalizedY: Float     // 32
    var velocityX: Float       // 36
    var velocityY: Float       // 40
    var size: Float            // 44
}

// Touch info for tracking finger positions and timing
private struct TouchInfo {
    var state: Int32
    var normalizedX: Float
    var normalizedY: Float
    var velocityX: Float
    var velocityY: Float
}

// Global storage for touch tracking
private var globalTouchInfoCallback: (([TouchInfo]) -> Void)?

// C callback function - MUST return Int32, not Void!
// Signature from MultitouchSupport.h: int (*MTContactCallbackFunction)(int, Finger*, int, double, int)
private let mtTouchCallback: @convention(c) (
    Int32,                      // device (not a pointer in this API)
    UnsafeMutableRawPointer?,   // touches (pointer to MTTouch/Finger array)
    Int32,                      // numTouches
    Double,                     // timestamp
    Int32                       // frame
) -> Int32 = { device, touchesPtr, numTouches, timestamp, frame in
    callbackInvokeCount += 1
    
    // Count fingers currently touching and collect touch info
    var touchingCount = 0
    var touchInfos: [TouchInfo] = []
    
    if let ptr = touchesPtr, numTouches > 0 {
        // MTTouch struct layout (with 8-byte alignment for double):
        // frame(4) + padding(4) + timestamp(8) + pathIndex(4) + state(4) + fingerID(4) + handID(4) + normalizedX(4) + normalizedY(4) + velocityX(4) + velocityY(4) + ...
        // Total size: 96 bytes
        let touchSize = 96
        
        // Offsets:
        // state: 20-23 (4 bytes)
        // normalizedX: 28-31 (4 bytes)
        // normalizedY: 32-35 (4 bytes)
        // velocityX: 36-39 (4 bytes)
        // velocityY: 40-43 (4 bytes)
        let stateOffset = 20
        let normalizedXOffset = 28
        let normalizedYOffset = 32
        let velocityXOffset = 36
        let velocityYOffset = 40
        
        for i in 0..<Int(numTouches) {
            let touchPtr = ptr.advanced(by: i * touchSize)
            let state = touchPtr.advanced(by: stateOffset).assumingMemoryBound(to: Int32.self).pointee
            let normalizedX = touchPtr.advanced(by: normalizedXOffset).assumingMemoryBound(to: Float.self).pointee
            let normalizedY = touchPtr.advanced(by: normalizedYOffset).assumingMemoryBound(to: Float.self).pointee
            let velocityX = touchPtr.advanced(by: velocityXOffset).assumingMemoryBound(to: Float.self).pointee
            let velocityY = touchPtr.advanced(by: velocityYOffset).assumingMemoryBound(to: Float.self).pointee
            
            // State values: 1=not tracking, 2=start, 3=hover, 4=touching, 5=break, 6=linger, 7=out
            // Count states 2, 3, 4 as "touching"
            if state >= 2 && state <= 4 {
                touchingCount += 1
                touchInfos.append(TouchInfo(
                    state: state,
                    normalizedX: normalizedX,
                    normalizedY: normalizedY,
                    velocityX: velocityX,
                    velocityY: velocityY
                ))
            }
        }
    }
    
    DispatchQueue.main.async {
        globalTouchCountCallback?(touchingCount)
        globalTouchInfoCallback?(touchInfos)
    }
    
    return 0  // Must return int
}

/// Bridge to MultitouchSupport.framework private API for raw touch detection
private enum MultitouchBridge {
    
    static var onTouchCountChanged: ((Int) -> Void)? {
        get { globalTouchCountCallback }
        set { globalTouchCountCallback = newValue }
    }
    
    static var onTouchInfoChanged: (([TouchInfo]) -> Void)? {
        get { globalTouchInfoCallback }
        set { globalTouchInfoCallback = newValue }
    }
    
    private static var devices: [UnsafeMutableRawPointer] = []
    private static var isRunning = false
    private static var frameworkHandle: UnsafeMutableRawPointer?
    
    static func start() {
        guard !isRunning else { return }
        
        // Load framework
        frameworkHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        guard frameworkHandle != nil else {
            print("👆 [MultitouchBridge] Failed to load MultitouchSupport.framework")
            return
        }
        print("👆 [MultitouchBridge] Framework loaded successfully")
        
        // Get function pointers
        guard let createListSym = dlsym(frameworkHandle, "MTDeviceCreateList"),
              let registerCallbackSym = dlsym(frameworkHandle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(frameworkHandle, "MTDeviceStart") else {
            print("👆 [MultitouchBridge] Failed to get function symbols")
            return
        }
        
        // Also get run loop scheduling functions
        let scheduleOnRunLoopSym = dlsym(frameworkHandle, "MTDeviceScheduleOnRunLoop")
        print("👆 [MultitouchBridge] Got function symbols, scheduleOnRunLoop=\(scheduleOnRunLoopSym != nil)")
        
        // Call MTDeviceCreateList - returns CFArrayRef (NSArray of MTDeviceRef)
        typealias CreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
        let createList = unsafeBitCast(createListSym, to: CreateListFunc.self)
        
        guard let unmanagedList = createList() else {
            print("👆 [MultitouchBridge] MTDeviceCreateList returned nil")
            return
        }
        
        let cfArray = unmanagedList.takeRetainedValue()
        let count = CFArrayGetCount(cfArray)
        print("👆 [MultitouchBridge] Device list count: \(count)")
        
        guard count > 0 else {
            print("👆 [MultitouchBridge] No multitouch devices found")
            return
        }
        
        // Extract device pointers from CFArray
        devices.removeAll()
        for i in 0..<count {
            if let devicePtr = CFArrayGetValueAtIndex(cfArray, i) {
                let device = UnsafeMutableRawPointer(mutating: devicePtr)
                devices.append(device)
                print("👆 [MultitouchBridge] Found device[\(i)]: \(device)")
            }
        }
        
        print("👆 [MultitouchBridge] Found \(devices.count) multitouch device(s)")
        
        // Register callback and start each device
        // Callback signature: int (*)(int device, Finger* data, int nFingers, double timestamp, int frame)
        typealias RegisterFunc = @convention(c) (UnsafeMutableRawPointer?, (@convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32)?) -> Void
        typealias StartFunc = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        typealias ScheduleFunc = @convention(c) (UnsafeMutableRawPointer?, CFRunLoop?, CFString?) -> Int32
        
        let registerCallback = unsafeBitCast(registerCallbackSym, to: RegisterFunc.self)
        let startDevice = unsafeBitCast(startSym, to: StartFunc.self)
        
        for device in devices {
            // Register the callback first
            registerCallback(device, mtTouchCallback)
            print("👆 [MultitouchBridge] Registered callback for device: \(device)")
            
            // Schedule on run loop if available (required for callbacks to fire)
            if let scheduleSym = scheduleOnRunLoopSym {
                let scheduleOnRunLoop = unsafeBitCast(scheduleSym, to: ScheduleFunc.self)
                let result = scheduleOnRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                print("👆 [MultitouchBridge] Scheduled on RunLoop, result=\(result)")
            }
            
            // Start the device
            let startResult = startDevice(device, 0)
            print("👆 [MultitouchBridge] Started device: \(device), result=\(startResult)")
        }
        
        isRunning = true
        print("👆 [MultitouchBridge] Started monitoring raw multitouch events")
    }
    
    static func stop() {
        guard isRunning, let handle = frameworkHandle else { return }
        
        if let stopSym = dlsym(handle, "MTDeviceStop") {
            typealias StopFunc = @convention(c) (UnsafeMutableRawPointer?) -> Void
            let stopDevice = unsafeBitCast(stopSym, to: StopFunc.self)
            
            for device in devices {
                stopDevice(device)
            }
        }
        
        devices.removeAll()
        isRunning = false
        print("👆 [MultitouchBridge] Stopped monitoring")
    }
}

/// V9: Advanced Input Monitor for global gestures
/// Detects Double-Option (left or right) and Three-Finger Double-Tap
/// Per v9.md Section 2: Technical Architecture - Input Layer
@MainActor
final class InputMonitor: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isDoubleOptionDetected: Bool = false
    @Published private(set) var isThreeFingerDoubleTapDetected: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when Double-Option is detected
    var onDoubleOptionTrigger: (() -> Void)?
    
    /// Called when Three-Finger Double-Tap is detected
    var onThreeFingerDoubleTap: (() -> Void)?
    
    // MARK: - Private Properties
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    // Double-Option detection state
    private var lastOptionPressTime: Date?
    private var optionPressCount: Int = 0
    private let doubleTapThreshold: TimeInterval = 0.3  // Max time between taps
    private var resetTimer: Timer?
    
    // Track modifier state to detect press events
    private var wasOptionPressed: Bool = false
    
    // Three-finger tap detection state
    private var lastThreeFingerTapTime: Date?
    private var threeFingerTapResetTimer: Timer?
    private var previousTouchCount: Int = 0
    private var touchDownTime: Date?
    private let tapMaxDuration: TimeInterval = 0.25  // Max duration for a "tap" (reduced from 0.3)
    
    // Enhanced detection: track finger positions and timing
    private var initialTouchPositions: [(x: Float, y: Float)] = []
    private var threeFingerStartTime: Date?  // When exactly 3 fingers first touched
    private var wasValidThreeFingerTouch: Bool = false
    private let maxMovementThreshold: Float = 0.05  // Max normalized movement (5% of trackpad)
    private let simultaneousTouchWindow: TimeInterval = 0.08  // All 3 fingers must touch within 80ms
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        Task { @MainActor in
            stopMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for global input events
    func startMonitoring() {
        guard globalMonitor == nil else {
            print("⌨️ [InputMonitor] Already monitoring")
            return
        }
        
        // Global monitor for when app is in background (keyboard)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        // Local monitor for when app is in foreground (keyboard)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
        
        // Start multitouch monitoring
        startMultitouchMonitoring()
        
        print("⌨️ [InputMonitor] Started monitoring for Double-Option and Three-Finger Double-Tap")
    }
    
    /// Stop monitoring for input events
    func stopMonitoring() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        
        // Stop multitouch bridge
        MultitouchBridge.stop()
        
        resetTimer?.invalidate()
        resetTimer = nil
        
        threeFingerTapResetTimer?.invalidate()
        threeFingerTapResetTimer = nil
        
        print("⌨️ [InputMonitor] Stopped monitoring")
    }
    
    // MARK: - Private Methods - Double Option Detection
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let isOptionPressed = event.modifierFlags.contains(.option)
        
        // Detect Option key DOWN event (transition from not pressed to pressed)
        if isOptionPressed && !wasOptionPressed {
            onOptionKeyPressed()
        }
        
        wasOptionPressed = isOptionPressed
    }
    
    private func onOptionKeyPressed() {
        let now = Date()
        
        // Check if this is within the double-tap window
        if let lastPress = lastOptionPressTime {
            let interval = now.timeIntervalSince(lastPress)
            
            if interval < doubleTapThreshold {
                // Double-Option detected!
                optionPressCount = 0
                lastOptionPressTime = nil
                resetTimer?.invalidate()
                
                print("⌨️ [InputMonitor] Double-Option DETECTED! (interval: \(String(format: "%.2f", interval))s)")
                isDoubleOptionDetected = true
                
                // Trigger callback
                onDoubleOptionTrigger?()
                
                // Reset detection state after a brief moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isDoubleOptionDetected = false
                }
                
                return
            }
        }
        
        // First press or outside window - start new detection
        lastOptionPressTime = now
        optionPressCount = 1
        
        // Set timer to reset if second press doesn't come
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: doubleTapThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetDetection()
            }
        }
    }
    
    private func resetDetection() {
        optionPressCount = 0
        lastOptionPressTime = nil
    }
}

// MARK: - Multitouch Support (Three-Finger Double-Tap)

extension InputMonitor {
    
    /// Start monitoring for multitouch trackpad events
    /// Uses MultitouchSupport.framework private API for raw touch detection
    func startMultitouchMonitoring() {
        print("👆 [InputMonitor] Setting up raw multitouch monitoring via MultitouchSupport.framework...")
        
        // Set up callback for touch count changes
        MultitouchBridge.onTouchCountChanged = { [weak self] touchCount in
            Task { @MainActor in
                self?.handleRawTouchCount(touchCount)
            }
        }
        
        // Set up callback for touch info updates (position/velocity tracking)
        MultitouchBridge.onTouchInfoChanged = { [weak self] touches in
            Task { @MainActor in
                self?.handleTouchInfoUpdate(touches)
            }
        }
        
        // Start the multitouch bridge
        MultitouchBridge.start()
        
        print("👆 [InputMonitor] Multitouch monitoring started")
    }
    
    /// Handle raw touch count from MultitouchSupport.framework
    private func handleRawTouchCount(_ touchCount: Int) {
        let now = Date()
        
        // Track when we first reach exactly 3 fingers
        if touchCount == 3 && previousTouchCount < 3 {
            // Check if fingers were added gradually (1->2->3) vs simultaneously
            if previousTouchCount == 0 {
                // All 3 fingers touched at once - this is a valid start
                threeFingerStartTime = now
                wasValidThreeFingerTouch = true
            } else if previousTouchCount > 0 {
                // Some fingers were already down - check timing
                if let startTime = touchDownTime {
                    let timeSinceFirstTouch = now.timeIntervalSince(startTime)
                    // If first finger was down for too long, this is likely 1+2 pattern
                    if timeSinceFirstTouch > simultaneousTouchWindow {
                        wasValidThreeFingerTouch = false
                    } else {
                        threeFingerStartTime = now
                        wasValidThreeFingerTouch = true
                    }
                } else {
                    // No start time recorded, be conservative
                    wasValidThreeFingerTouch = false
                }
            }
            touchDownTime = now
        } else if touchCount > 0 && previousTouchCount == 0 {
            // First finger(s) touched - record time
            touchDownTime = now
        } else if touchCount < 3 && previousTouchCount == 3 {
            // Three fingers just lifted
            if wasValidThreeFingerTouch, let downTime = threeFingerStartTime {
                let duration = now.timeIntervalSince(downTime)
                
                // Check if it was a quick tap (not a hold)
                if duration < tapMaxDuration {
                    onThreeFingerTapDetected()
                }
            }
            threeFingerStartTime = nil
            wasValidThreeFingerTouch = false
        } else if touchCount == 0 {
            // All fingers lifted - reset state
            touchDownTime = nil
            threeFingerStartTime = nil
            wasValidThreeFingerTouch = false
            initialTouchPositions.removeAll()
        }
        
        previousTouchCount = touchCount
    }
    
    /// Handle touch info updates for movement detection
    fileprivate func handleTouchInfoUpdate(_ touches: [TouchInfo]) {
        // Only track when we have exactly 3 fingers
        guard touches.count == 3 else { return }
        
        // Record initial positions when 3 fingers first touch
        if initialTouchPositions.isEmpty {
            initialTouchPositions = touches.map { (x: $0.normalizedX, y: $0.normalizedY) }
            return
        }
        
        // Check if any finger has moved too much (indicates swipe)
        for touch in touches {
            // Check velocity - high velocity indicates swipe
            let velocity = sqrt(touch.velocityX * touch.velocityX + touch.velocityY * touch.velocityY)
            if velocity > 1.0 {  // Velocity threshold for swipe detection
                wasValidThreeFingerTouch = false
                return
            }
        }
        
        // Check total movement from initial positions
        for (i, touch) in touches.enumerated() {
            if i < initialTouchPositions.count {
                let dx = touch.normalizedX - initialTouchPositions[i].x
                let dy = touch.normalizedY - initialTouchPositions[i].y
                let distance = sqrt(dx * dx + dy * dy)
                
                if distance > maxMovementThreshold {
                    wasValidThreeFingerTouch = false
                    return
                }
            }
        }
    }
    
    /// Called when a three-finger tap is detected
    private func onThreeFingerTapDetected() {
        let now = Date()
        
        // Check if this is within the double-tap window
        if let lastTap = lastThreeFingerTapTime {
            let interval = now.timeIntervalSince(lastTap)
            
            if interval < doubleTapThreshold {
                // Double-tap detected!
                lastThreeFingerTapTime = nil
                threeFingerTapResetTimer?.invalidate()
                
                print("👆 [InputMonitor] Three-Finger Double-Tap DETECTED! (interval: \(String(format: "%.2f", interval))s)")
                isThreeFingerDoubleTapDetected = true
                
                // Trigger callback (same as Double-Cmd)
                onThreeFingerDoubleTap?()
                
                // Reset detection state after a brief moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isThreeFingerDoubleTapDetected = false
                }
                
                return
            }
        }
        
        // First tap or outside window - start new detection
        lastThreeFingerTapTime = now
        
        // Set timer to reset if second tap doesn't come
        threeFingerTapResetTimer?.invalidate()
        threeFingerTapResetTimer = Timer.scheduledTimer(withTimeInterval: doubleTapThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lastThreeFingerTapTime = nil
            }
        }
            }
}

