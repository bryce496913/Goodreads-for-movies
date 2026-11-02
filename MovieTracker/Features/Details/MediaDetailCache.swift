import Foundation

/// Session-only domain snapshots, no disk storage or custom artwork cache.
@MainActor
final class MediaDetailCache {
    struct Snapshot {
        let media: MediaSearchResult
        var extrasAttemptedAt: Date? = nil
        var cast: [CastMember] = []
        var imageResolver: MetadataImageResolver?
    }

    private let clock: @Sendable () -> Date
    private var values: [MediaID: Snapshot] = [:]
    private var order: [MediaID] = []
    private let capacity: Int

    init(capacity: Int = 20, clock: @escaping @Sendable () -> Date = { .now }) { self.capacity = max(1, capacity); self.clock = clock }

    func snapshot(for id: MediaID) -> Snapshot? {
        guard let value = values[id] else { return nil }
        guard MetadataPolicy.mayDisplay(value.media, at: clock()) else { values[id] = nil; order.removeAll { $0 == id }; return nil }
        return value
    }

    func clear() { values.removeAll(); order.removeAll() }
    func expire(at now: Date) {
        for id in order where values[id].map({ !MetadataPolicy.mayDisplay($0.media, at: now) }) == true { values[id] = nil }
        order.removeAll { values[$0] == nil }
        for id in order {
            if MetadataPolicy.isTMDB(id), let resolver = values[id]?.imageResolver, !MetadataPolicy.isUsable(resolver.metadataRetrievedAt, at: now) { values[id]?.imageResolver = nil }
        }
    }

    func save(_ snapshot: Snapshot, for id: MediaID) {
        if values[id] == nil { order.append(id) }
        values[id] = snapshot
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }
}
