import SwiftData
import SwiftUI

@main
struct MovieTrackerApp: App {
    @State private var container: ModelContainer?
    @State private var persistenceFailed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    AppRootView()
                        .modelContainer(container)
                } else if persistenceFailed {
                    ContentUnavailableView {
                        Label("Library unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your local library could not be opened. Try again to continue. Your saved data has not been reset.")
                    } actions: {
                        Button("Try Again", action: loadPersistence)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("Opening your library…")
                }
            }
            .task {
                if container == nil && !persistenceFailed {
                    loadPersistence()
                }
            }
        }
    }

    @MainActor
    private func loadPersistence() {
        do {
            container = try PersistenceController.makeContainer()
            persistenceFailed = false
        } catch {
            persistenceFailed = true
        }
    }
}
