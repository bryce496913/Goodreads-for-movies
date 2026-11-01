import Foundation
import SwiftData

enum PersistenceController {
    /// No seed data and no CloudKit. Tests use an isolated in-memory store.
    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredLibraryEntry.self, StoredPersonalReview.self, StoredViewingEvent.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Explicit local URL for isolated disk persistence tests. The app keeps its default store.
    @MainActor
    static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema([StoredLibraryEntry.self, StoredPersonalReview.self, StoredViewingEvent.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
