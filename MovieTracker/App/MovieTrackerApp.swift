import SwiftData
import SwiftUI

@main
struct MovieTrackerApp: App {
    @State private var library: LibraryStore?
    @State private var container: ModelContainer?
    @State private var persistenceFailed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let container, let library {
                    AppRootView()
                        .environment(library)
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
            #if DEBUG
            let inMemory = ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
            #else
            let inMemory = false
            #endif
            #if DEBUG
            if inMemory, let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-testing-library-store=") }),
               let identifier = UUID(uuidString: String(argument.dropFirst("--ui-testing-library-store=".count))) {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
                let directory = support.appendingPathComponent("LibraryUITests", isDirectory: true)
                    .appendingPathComponent(identifier.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                container = try PersistenceController.makeContainer(at: directory.appendingPathComponent("Library.store"))
            } else {
                container = try PersistenceController.makeContainer(inMemory: inMemory)
            }
            #else
            container = try PersistenceController.makeContainer()
            #endif
            if let container {
                let store = LibraryStore(container: container)
                #if DEBUG
                if inMemory && ProcessInfo.processInfo.arguments.contains("--ui-testing-library-organization") {
                    try LibraryOrganizationUITestData.seed(store)
                }
                #endif
                library = store
            }
            persistenceFailed = false
        } catch {
            persistenceFailed = true
        }
    }
}
