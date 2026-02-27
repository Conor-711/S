import Foundation
import AVFoundation

/// Service for playing sound effects
@MainActor
class SoundEffectService: ObservableObject {
    static let shared = SoundEffectService()
    
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    /// Play capture sound effect
    func playCaptureSound() {
        guard let soundURL = Bundle.main.url(forResource: "capture_sound", withExtension: "mp3") else {
            print("⚠️ [SoundEffect] Capture sound file not found")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("🔊 [SoundEffect] Playing capture sound")
        } catch {
            print("❌ [SoundEffect] Failed to play sound: \(error)")
        }
    }
    
    /// Stop any currently playing sound
    func stopSound() {
        audioPlayer?.stop()
    }
}
