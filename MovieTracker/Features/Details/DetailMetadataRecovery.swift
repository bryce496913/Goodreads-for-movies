import Foundation

/// Availability of optional provider fields is not proof that a request failed.
/// Missing fields invite an explicit refresh; they never bypass the 30-day automatic policy.
enum DetailMetadataRecovery {
    static func missingFields(in media: MediaSearchResult) -> [String] {
        var fields: [String] = []
        switch media {
        case .movie(let value):
            if value.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("synopsis") }
            if value.genres.isEmpty { fields.append("genres") }
            if value.runtimeMinutes.map({ $0 > 0 }) != true { fields.append("runtime") }
            if value.posterReference == nil && value.backdropReference == nil { fields.append("artwork") }
        case .tvShow(let value):
            if value.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("synopsis") }
            if value.genres.isEmpty { fields.append("genres") }
            if value.seasons == nil { fields.append("season list") }
            if value.posterReference == nil && value.backdropReference == nil { fields.append("artwork") }
        }
        return fields
    }
}
