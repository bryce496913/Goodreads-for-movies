import Foundation
import SwiftData

enum PersistenceController {
    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try open(schema: schema, configuration: configuration)
    }

    /// Explicit URL is used by disk regression tests. The app retains SwiftData's default URL/name.
    @MainActor
    static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try open(schema: schema, configuration: configuration)
    }

    @MainActor
    static func open(schema: Schema, configuration: ModelConfiguration,
                     migrationPlan: any SchemaMigrationPlan.Type = LibraryMigrationPlan.self) throws -> ModelContainer {
        var backup: URL?
        if !configuration.isStoredInMemoryOnly {
            let url = configuration.url
            let files = FileManager.default
            if files.fileExists(atPath: url.path) {
                do { backup = try StoreSafetyBackup.create(for: url) }
                catch { throw PersistenceOpenError(stage: .backup, backupDirectory: nil, code: (error as? StoreSafetyBackup.Failure).map { Int($0.code) }) }
                do { try StoreSchemaRecognition.validate(url, supported: migrationPlan.schemas) }
                catch { throw PersistenceOpenError(stage: .schemaCheck, backupDirectory: backup, code: (error as NSError).code) }
            } else if ["-wal", "-shm"].contains(where: { files.fileExists(atPath: url.path + $0) }) {
                // A missing main store with surviving journals is not a new installation.
                throw PersistenceOpenError(stage: .incompleteStore, backupDirectory: nil, code: nil)
            }
        }
        do {
            return try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: [configuration])
        } catch {
            // Never retry with an unversioned schema, a different URL, an empty store or in-memory storage.
            throw PersistenceOpenError(stage: .open, backupDirectory: backup, code: (error as NSError).code)
        }
    }
}

struct PersistenceOpenError: Error, LocalizedError {
    enum Stage: String { case backup, schemaCheck, open, incompleteStore }
    let stage: Stage
    let backupDirectory: URL?
    let code: Int?
    var errorDescription: String? {
        let diagnostic = "Diagnostic: \(stage.rawValue)" + (code.map { " (\($0))" } ?? "") + "."
        switch stage {
        case .backup: return "A safety backup of the existing library could not be completed. The app did not attempt to open or migrate it. Free storage or resolve access issues, then retry. " + diagnostic
        case .schemaCheck: return "The existing store could not be matched safely to a retained schema. No migration or empty replacement was attempted. Its complete safety backup is retained in StoreSafetyBackups. " + diagnostic
        case .incompleteStore: return "The main library file is missing but database journals remain. No empty replacement was created. Preserve the files for recovery. " + diagnostic
        case .open: return "The library could not be opened or migrated. No reset or empty-store fallback was attempted. "
            + (backupDirectory == nil ? "" : "A complete pre-open safety backup is retained in StoreSafetyBackups for recovery. ") + diagnostic
        }
    }
}
