import Foundation

/// Session-only domain snapshots, no disk storage or custom artwork cache.
@MainActor
final class MediaDetailCache {
    struct Snapshot {
        let media: MediaSearchResult
        var cast: [CastMember] = []
        var imageResolver: MetadataImageResolver?
    }

    private var values: [MediaID: Snapshot] = [:]
    private var order: [MediaID] = []
    private let capacity: Int

    init(capacity: Int = 20) { self.capacity = max(1, capacity) }

    func snapshot(for id: MediaID) -> Snapshot? { values[id] }

    func save(_ snapshot: Snapshot, for id: MediaID) {
        if values[id] == nil { order.append(id) }
        values[id] = snapshot
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }
}
