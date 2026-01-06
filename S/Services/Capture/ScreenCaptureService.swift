import Foundation
import AppKit
import ScreenCaptureKit
import Combine

/// Service for capturing screen content using ScreenCaptureKit
@MainActor
final class ScreenCaptureService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentScreenshot: NSImage?
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var captureError: String?
    
    // MARK: - Private Properties
    
    private var pollingTimer: Timer?
    private var previousImageData: Data?
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var currentDisplayID: CGDirectDisplayID?
    
    // MARK: - Public Methods
    
    /// Start polling for screen changes at the specified interval
    /// - Parameter interval: Time interval between capture attempts in seconds
    func startPolling(interval: TimeInterval = 1.0) {
        guard !isCapturing else { return }
        
        isCapturing = true
        captureError = nil
        
        print("📸 [ScreenCapture] Starting polling with interval: \(interval)s")
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureScreen()
            }
        }
        
        Task {
            await captureScreen()
        }
    }
    
    /// Stop the polling timer
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isCapturing = false
        stream?.stopCapture()
        stream = nil
    }
    
    /// Capture a single screenshot
    func captureScreen() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = content.displays.first else {
                captureError = "No display found"
                return
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(display.width)
            configuration.height = Int(display.height)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            
            if ImageDiffer.hasImageChanged(nsImage, comparedTo: previousImageData) {
                previousImageData = ImageDiffer.imageToData(nsImage)
                currentScreenshot = nsImage
                print("📸 [ScreenCapture] New screenshot captured (\(image.width)x\(image.height))")
            } else {
                print("📸 [ScreenCapture] Screen unchanged, skipping")
            }
            
        } catch {
            captureError = "Capture failed: \(error.localizedDescription)"
            print("📸 [ScreenCapture] ERROR: \(error)")
        }
    }
    
    /// Request screen capture permission
    /// - Returns: true if permission is granted
    func requestPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let hasPermission = !content.displays.isEmpty
            print("📸 [ScreenCapture] Permission check: \(hasPermission ? "GRANTED" : "DENIED"), displays: \(content.displays.count)")
            return hasPermission
        } catch {
            print("📸 [ScreenCapture] Permission request FAILED: \(error)")
            return false
        }
    }
    
    // MARK: - Phase 4: Multi-Monitor Support
    
    /// Update the target screen for capture
    /// - Parameter displayID: The CGDirectDisplayID of the target display
    func updateTargetScreen(displayID: CGDirectDisplayID) {
        guard displayID != currentDisplayID else { return }
        
        print("📸 [ScreenCapture] Switching to display: \(displayID)")
        currentDisplayID = displayID
        previousImageData = nil  // Reset to force new capture
        
        // Force immediate capture on new display
        Task {
            await captureScreenForDisplay(displayID: displayID)
        }
    }
    
    /// Capture screen for a specific display
    private func captureScreenForDisplay(displayID: CGDirectDisplayID) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                captureError = "Display not found"
                return
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(display.width)
            configuration.height = Int(display.height)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            
            if ImageDiffer.hasImageChanged(nsImage, comparedTo: previousImageData) {
                previousImageData = ImageDiffer.imageToData(nsImage)
                currentScreenshot = nsImage
                print("📸 [ScreenCapture] New screenshot from display \(displayID) (\(image.width)x\(image.height))")
            }
            
        } catch {
            captureError = "Capture failed: \(error.localizedDescription)"
            print("📸 [ScreenCapture] ERROR on display \(displayID): \(error)")
        }
    }
}

// MARK: - Stream Output Handler

private class StreamOutput: NSObject, SCStreamOutput {
    var frameHandler: ((CMSampleBuffer) -> Void)?
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        frameHandler?(sampleBuffer)
    }
}

// MARK: - CMSampleBuffer Extension

extension CMSampleBuffer {
    var nsImage: NSImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
