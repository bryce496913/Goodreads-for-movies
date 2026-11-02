import Foundation

/// Conservative operational policy below the terms' six-month ceiling; not a license exemption.
enum MetadataPolicy {
    static let retention: TimeInterval = 150 * 86_400
    static let refreshInterval: TimeInterval = 30 * 86_400
    static let retryInterval: TimeInterval = 15 * 60
    static func retryDelay(_ header: String?, at now: Date) -> TimeInterval {
        if let seconds = header.flatMap(TimeInterval.init), seconds.isFinite, seconds >= 0 { return max(retryInterval, seconds) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .gmt
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = header.flatMap({ formatter.date(from: $0) }) { return max(retryInterval, date.timeIntervalSince(now)) }
        return retryInterval
    }
    static func isTMDB(_ id: MediaID) -> Bool { id.value.hasPrefix("tmdb:") }
    static func isUsable(_ date: Date?, at now: Date) -> Bool {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite,
              date <= now else { return false }
        return now.timeIntervalSince(date) < retention
    }
    static func refreshEligible(_ date: Date?, at now: Date) -> Bool {
        !isUsable(date, at: now) || date.map { now.timeIntervalSince($0) >= refreshInterval } == true
    }
    static func placeholder(_ id: MediaID) -> String {
        "Metadata unavailable — \(id.kind == .movie ? "movie" : "TV") \(id.value)"
    }
    static func mayDisplay(_ media: MediaSearchResult, at now: Date) -> Bool {
        !isTMDB(SearchItem(media).id) || isUsable(media.metadataRetrievedAt, at: now)
    }
    static func placeholderMedia(_ id: MediaID) -> MediaSearchResult {
        switch id.kind {
        case .movie: .movie(Movie(id: id.value, title: placeholder(id)))
        case .tvShow: .tvShow(TVShow(id: id.value, title: placeholder(id)))
        }
    }
    static func forDisplay(_ media: MediaSearchResult, at now: Date) -> MediaSearchResult {
        mayDisplay(media, at: now) ? media : placeholderMedia(SearchItem(media).id)
    }
}

extension MediaSearchResult {
    var metadataRetrievedAt: Date? {
        switch self { case .movie(let movie): movie.metadataRetrievedAt; case .tvShow(let show): show.metadataRetrievedAt }
    }
}

@MainActor
enum MetadataRuntimeGate {
    // Factory gate, updated before the app root is presented and after maintenance.
    static var blockingReason: String?
    static var credentialEpoch = 0
    static func authorize(_ epoch: Int) throws {
        guard blockingReason == nil else { throw MetadataError.retentionBlocked }
        guard epoch == credentialEpoch else { throw MetadataError.missingCredential }
    }
}
