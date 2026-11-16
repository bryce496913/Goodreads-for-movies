import Foundation
import SwiftData

extension LibraryStore {
    func isInCollection(_ collection: UUID, mediaID: MediaID) -> Bool {
        _ = revision
        return collectionIDsByMedia[mediaID]?.contains(collection) == true
    }
    func members(of collection: UUID) -> [StoredCollectionMembership] {
        _ = revision
        return membershipsByCollection[collection] ?? []
    }
    @discardableResult
    func saveCollection(id: UUID = UUID(), name: String, now: Date = .now) throws -> UUID {
        if let loadError { throw loadError }
        let valid = try CollectionName.validated(name)
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CollectionError.invalidName }
        try writeTransaction { context in
            let rows = try context.fetch(FetchDescriptor<StoredCollection>())
            guard !rows.contains(where: { $0.id != id && CollectionName.key($0.name) == CollectionName.key(valid) }) else { throw CollectionError.duplicateName }
            let matches = rows.filter { $0.id == id }
            guard matches.count <= 1 else { throw LibraryStoreError.duplicateRecords }
            if let existing = matches.first {
                if existing.name != valid { existing.name = valid; existing.updatedAt = now }
            } else { context.insert(StoredCollection(id: id, name: valid, createdAt: now, updatedAt: now)) }
        }
        return id
    }
    func deleteCollection(_ id: UUID) throws {
        if let loadError { throw loadError }
        try writeTransaction { context in
            for row in try context.fetch(FetchDescriptor<StoredCollectionMembership>()) where row.collectionID == id { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<StoredCollection>()) where row.id == id { context.delete(row) }
        }
    }
    func setCollectionMembership(_ selected: Bool, collection: UUID, media: MediaSearchResult, now: Date = .now) throws {
        if let loadError { throw loadError }
        let identity = SearchItem(media).id
        guard now.timeIntervalSinceReferenceDate.isFinite, !identity.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, identity.value.utf8.count <= 1_024 else { throw CollectionError.unavailable }
        try writeTransaction { context in
            guard let owner = try context.fetch(FetchDescriptor<StoredCollection>()).first(where: { $0.id == collection }) else { throw CollectionError.unavailable }
            let ordered = members(of: collection)
            let matches = ordered.filter { $0.mediaID == identity }
            guard matches.count <= 1 else { throw LibraryStoreError.duplicateRecords }
            if selected {
                guard matches.isEmpty else { return }
                _ = try ensureLibraryEntry(media: media) // A statusless snapshot row; never infer Watchlist/Watched.
                context.insert(StoredCollectionMembership(collectionID: collection, mediaID: identity, position: ordered.count, addedAt: now))
            } else {
                guard let removed = matches.first else { return }
                context.delete(removed)
                for (position, row) in ordered.filter({ $0.id != removed.id }).enumerated() where row.position != position { row.position = position }
            }
            owner.updatedAt = now
        }
    }
    func removeCollectionMembers(_ id: UUID, memberships: Set<UUID>, now: Date = .now) throws {
        if let loadError { throw loadError }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CollectionError.invalidOrder }
        try writeTransaction { context in
            guard let owner = collections.first(where: { $0.id == id }) else { throw CollectionError.unavailable }
            let rows = members(of: id)
            guard memberships.isSubset(of: Set(rows.map(\.id))) else { throw CollectionError.invalidOrder }
            guard !memberships.isEmpty else { return }
            for row in rows where memberships.contains(row.id) { context.delete(row) }
            for (position, row) in rows.filter({ !memberships.contains($0.id) }).enumerated() where row.position != position { row.position = position }
            owner.updatedAt = now
        }
    }
    func reorderCollection(_ id: UUID, memberships: [UUID], original: [UUID]? = nil, now: Date = .now) throws {
        if let loadError { throw loadError }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CollectionError.invalidOrder }
        try writeTransaction { _ in
            guard let owner = collections.first(where: { $0.id == id }) else { throw CollectionError.unavailable }
            let rows = members(of: id)
            guard original == nil || original == rows.map(\.id), memberships.count == rows.count, Set(memberships).count == memberships.count,
                  Set(memberships) == Set(rows.map(\.id)) else { throw CollectionError.invalidOrder }
            let positions = Dictionary(uniqueKeysWithValues: memberships.enumerated().map { ($0.element, $0.offset) })
            var changed = false
            for row in rows where row.position != positions[row.id] { row.position = positions[row.id]!; changed = true }
            if changed { owner.updatedAt = now }
        }
    }
}
