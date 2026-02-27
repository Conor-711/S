import Foundation
import SwiftUI

#if canImport(Sparkle)
import Sparkle

// MARK: - Sparkle Updater Controller

/// Manages Sparkle auto-update functionality
final class SparkleUpdaterController: ObservableObject {
    
    static let shared = SparkleUpdaterController()
    
    private let updaterController: SPUStandardUpdaterController
    
    /// Published property to track if updates can be checked
    @Published var canCheckForUpdates: Bool = false
    
    private init() {
        // Initialize Sparkle updater
        // startingUpdater: true means it will automatically check for updates on launch
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Observe canCheckForUpdates property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
        print("✨ [SparkleUpdater] Initialized with auto-update enabled")
    }
    
    /// The underlying SPUUpdater instance
    var updater: SPUUpdater {
        updaterController.updater
    }
    
    /// Manually check for updates
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
        print("✨ [SparkleUpdater] Manual update check triggered")
    }
    
    /// Check if automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }
    
    /// Get the update check interval
    var updateCheckInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }
    
    /// Get the last update check date
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
}

// MARK: - SwiftUI Check for Updates View

/// SwiftUI view for the "Check for Updates" menu item
struct CheckForUpdatesView: View {
    @ObservedObject private var updaterController = SparkleUpdaterController.shared
    
    var body: some View {
        Button("Check for Updates…") {
            updaterController.checkForUpdates()
        }
        .disabled(!updaterController.canCheckForUpdates)
    }
}

// MARK: - Update Settings View

/// SwiftUI view for update settings
struct UpdateSettingsView: View {
    @ObservedObject private var updaterController = SparkleUpdaterController.shared
    @State private var automaticallyChecks: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Software Updates")
                .font(.headline)
            
            Toggle("Automatically check for updates", isOn: $automaticallyChecks)
                .onChange(of: automaticallyChecks) { _, newValue in
                    updaterController.automaticallyChecksForUpdates = newValue
                }
            
            if let lastCheck = updaterController.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck, formatter: dateFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Check for Updates Now") {
                updaterController.checkForUpdates()
            }
            .disabled(!updaterController.canCheckForUpdates)
        }
        .onAppear {
            automaticallyChecks = updaterController.automaticallyChecksForUpdates
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

#else

// MARK: - Fallback when Sparkle is not available

/// Stub controller when Sparkle is not imported
final class SparkleUpdaterController: ObservableObject {
    static let shared = SparkleUpdaterController()
    @Published var canCheckForUpdates: Bool = false
    
    private init() {
        print("⚠️ [SparkleUpdater] Sparkle framework not available")
    }
    
    func checkForUpdates() {
        print("⚠️ [SparkleUpdater] Cannot check for updates - Sparkle not available")
    }
}

/// Stub view when Sparkle is not available
struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates…") { }
            .disabled(true)
    }
}

/// Stub settings view when Sparkle is not available
struct UpdateSettingsView: View {
    var body: some View {
        Text("Software updates are not available")
            .foregroundColor(.secondary)
    }
}

#endif
