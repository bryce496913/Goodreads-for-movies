#if DEBUG
import Foundation

/// Only called for an explicit organization-test flag inside an already isolated UI-test store.
@MainActor
enum LibraryOrganizationUITestData {
    static func seed(_ store: LibraryStore) throws {
        guard store.entries.isEmpty else { return }
        try store.writeTransaction { context in
            for index in 0..<250 {
                let kind: MediaID.Kind = index == 1 || index == 3 || (index >= 4 && index.isMultiple(of: 2)) ? .tvShow : .movie
                let title: String
                switch index {
                case 0: title = "Café Society"
                case 1: title = "Café Chronicles"
                case 2: title = "Alpha"
                case 3: title = "No Status Favorite"
                default: title = "Library Fixture \(index)"
                }
                let status: LibraryStatus? = index == 3 ? nil : (index == 0 ? .watched : (kind == .tvShow ? .watching : .watchlist))
                let id = MediaID(kind: kind, value: "fixture:library:\(index)")
                let entry = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: id, status: status,
                    isFavorite: [0, 1, 3].contains(index), addedAt: Date(timeIntervalSince1970: 1_577_836_800 + Double(index))))
                entry.savedTitle = title
                entry.savedYear = index == 0 ? 2016 : (index == 1 ? 2024 : nil)
                entry.ratingHalfStarUnits = index == 0 ? 9 : (index == 1 ? 8 : nil)
                let media: MediaSearchResult = kind == .movie ? .movie(Movie(id: id.value, title: title, releaseDate: index == 0 ? Date(timeIntervalSince1970: 1_451_606_400) : nil))
                    : .tvShow(TVShow(id: id.value, title: title, firstAirDate: index == 1 ? Date(timeIntervalSince1970: 1_704_067_200) : nil, seasons: []))
                entry.snapshotData = try JSONEncoder().encode(media)
                context.insert(entry)
            }
        }
    }
}
#endif
