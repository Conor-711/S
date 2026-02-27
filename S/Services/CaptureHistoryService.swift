import Foundation
import AppKit

// MARK: - Captured Item Model
/// Represents a captured screenshot with its associated Atom data
struct CapturedItem: Identifiable, Codable {
    let id: UUID
    let capturedAt: Date
    let atom: Atom?
    let screenshotPath: String?  // Path to saved screenshot
    
    // Transient property - not saved
    var screenshot: NSImage? {
        guard let path = screenshotPath else { return nil }
        return NSImage(contentsOfFile: path)
    }
    
    init(id: UUID = UUID(), capturedAt: Date = Date(), atom: Atom? = nil, screenshotPath: String? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.atom = atom
        self.screenshotPath = screenshotPath
    }
    
    enum CodingKeys: String, CodingKey {
        case id, capturedAt, atom, screenshotPath
    }
}

// MARK: - Capture History Service
/// Manages the history of captured screenshots and their Atoms
@MainActor
final class CaptureHistoryService: ObservableObject {
    
    static let shared = CaptureHistoryService()
    
    @Published private(set) var items: [CapturedItem] = []
    
    private let fileManager = FileManager.default
    private let maxItems = 100  // Keep last 100 captures
    
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("S", isDirectory: true)
        let capturesDir = appDir.appendingPathComponent("Captures", isDirectory: true)
        return capturesDir
    }
    
    private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("history.json")
    }
    
    private init() {
        setupStorageDirectory()
        loadHistory()
    }
    
    // MARK: - Setup
    
    private func setupStorageDirectory() {
        do {
            if !fileManager.fileExists(atPath: storageDirectory.path) {
                try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                print("📁 [CaptureHistory] Created storage directory: \(storageDirectory.path)")
            }
        } catch {
            print("❌ [CaptureHistory] Failed to create storage directory: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Add a new captured item with screenshot and atom
    func addCapture(screenshot: NSImage, atom: Atom?) {
        let id = UUID()
        let screenshotPath = saveScreenshot(screenshot, id: id)
        
        let item = CapturedItem(
            id: id,
            capturedAt: Date(),
            atom: atom,
            screenshotPath: screenshotPath
        )
        
        items.insert(item, at: 0)
        
        // Trim to max items
        if items.count > maxItems {
            let removedItems = items.suffix(from: maxItems)
            for item in removedItems {
                deleteScreenshot(item.screenshotPath)
            }
            items = Array(items.prefix(maxItems))
        }
        
        saveHistory()
        print("📸 [CaptureHistory] Added capture: \(id), atom type: \(atom?.type.rawValue ?? "none")")
    }
    
    /// Clear all history
    func clearHistory() {
        for item in items {
            deleteScreenshot(item.screenshotPath)
        }
        items.removeAll()
        saveHistory()
        print("🗑️ [CaptureHistory] History cleared")
    }
    
    /// Delete a specific item
    func deleteItem(_ item: CapturedItem) {
        deleteScreenshot(item.screenshotPath)
        items.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    // MARK: - Private Methods
    
    private func saveScreenshot(_ image: NSImage, id: UUID) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("❌ [CaptureHistory] Failed to convert screenshot to PNG")
            return nil
        }
        
        let filePath = storageDirectory.appendingPathComponent("\(id.uuidString).png")
        
        do {
            try pngData.write(to: filePath)
            return filePath.path
        } catch {
            print("❌ [CaptureHistory] Failed to save screenshot: \(error)")
            return nil
        }
    }
    
    private func deleteScreenshot(_ path: String?) {
        guard let path = path else { return }
        try? fileManager.removeItem(atPath: path)
    }
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            print("📁 [CaptureHistory] No history file found, starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            items = try JSONDecoder().decode([CapturedItem].self, from: data)
            print("📁 [CaptureHistory] Loaded \(items.count) items from history")
        } catch {
            print("❌ [CaptureHistory] Failed to load history: \(error)")
        }
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyFileURL)
        } catch {
            print("❌ [CaptureHistory] Failed to save history: \(error)")
        }
    }
}
