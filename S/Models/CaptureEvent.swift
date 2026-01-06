import Foundation
import AppKit

/// V10: Event published when a screen capture occurs
/// Used for fly-in animation in MorphingHUDView
struct CaptureEvent: Identifiable {
    let id = UUID()
    let thumbnail: NSImage?
    let timestamp: Date = Date()
}
