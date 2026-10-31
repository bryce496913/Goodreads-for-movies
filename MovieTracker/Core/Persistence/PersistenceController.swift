import SwiftData

enum PersistenceController {
    /// No seed data and no CloudKit. Tests use an isolated in-memory store.
    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredLibraryEntry.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
