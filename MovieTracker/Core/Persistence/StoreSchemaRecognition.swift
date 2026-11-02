import CoreData
import Foundation
import SwiftData

/// Match public Core Data entity-version hashes before SwiftData can migrate an existing store.
/// Reference stores are empty, disposable UUID paths, never the app's data URL or a fallback container.
@MainActor
enum StoreSchemaRecognition {
    struct Unrecognized: Error {}
    private static var referenceHashes: [String: [String: Data]] = [:]

    static func validate(_ url: URL, supported: [any VersionedSchema.Type]) throws {
        let source = try hashes(at: url)
        for version in supported.reversed() {
            let key = String(reflecting: version)
            let known: [String: Data]
            if let cached = referenceHashes[key] { known = cached }
            else {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SchemaReference-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let referenceURL = directory.appendingPathComponent("Reference.store")
                known = try autoreleasepool {
                    let schema = Schema(versionedSchema: version)
                    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: referenceURL, cloudKitDatabase: .none)])
                    // Keep the container alive through metadata reading. No records or user data are inserted.
                    return try withExtendedLifetime(container) { try hashes(at: referenceURL) }
                }
                referenceHashes[key] = known
                // OS temporary storage owns cleanup. Do not unlink a store with potentially retained framework handles.
            }
            if source == known { return }
        }
        throw Unrecognized()
    }
    private static func hashes(at url: URL) throws -> [String: Data] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url,
            options: [NSReadOnlyPersistentStoreOption: true])
        guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data], !hashes.isEmpty else { throw Unrecognized() }
        return hashes
    }
}
