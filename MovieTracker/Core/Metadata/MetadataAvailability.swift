import Foundation

/// Describes retained content, not inferred reachability. Connectivity is only known after a request.
enum MetadataAvailability: Equatable, Sendable {
    case saved(Date?), refreshDue(Date), expired(Date), unavailable

    static func resolve(media: MediaSearchResult?, lastRetrieved: Date?, at now: Date) -> Self {
        if let media, MetadataPolicy.mayDisplay(media, at: now) {
            let date = media.metadataRetrievedAt
            if MetadataPolicy.isTMDB(SearchItem(media).id), let date, MetadataPolicy.refreshEligible(date, at: now) { return .refreshDue(date) }
            return .saved(date)
        }
        if let date = lastRetrieved, date <= now, date.timeIntervalSinceReferenceDate.isFinite,
           !MetadataPolicy.isUsable(date, at: now) { return .expired(date) }
        return .unavailable
    }
    static func receipt(_ date: Date?, at now: Date) -> Self {
        guard let date else { return .unavailable }
        if MetadataPolicy.isUsable(date, at: now) {
            return MetadataPolicy.refreshEligible(date, at: now) ? .refreshDue(date) : .saved(date)
        }
        return date <= now && date.timeIntervalSinceReferenceDate.isFinite ? .expired(date) : .unavailable
    }
    var retrievedAt: Date? {
        switch self { case .saved(let date): date; case .refreshDue(let date), .expired(let date): date; case .unavailable: nil }
    }
    var message: String {
        switch self {
        case .saved: "Saved metadata is available on this device. Opening it does not require a connection."
        case .refreshDue: "Saved metadata is available offline. An update is due when the provider is reachable."
        case .expired: "Saved provider metadata expired and was removed. Your ratings, reviews, diary and watched flags remain available."
        case .unavailable: "No usable provider metadata is saved on this device. Your personal records remain available by identifier."
        }
    }
}
