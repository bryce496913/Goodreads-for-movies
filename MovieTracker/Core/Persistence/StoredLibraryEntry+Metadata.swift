import Foundation

extension StoredLibraryEntry {
    var mediaID: MediaID? {
        guard let kind = MediaID.Kind(rawValue: mediaKind) else { return nil }
        return MediaID(kind: kind, value: mediaValue)
    }

    var savedMedia: MediaSearchResult? {
        guard let snapshotData, let media = try? JSONDecoder().decode(MediaSearchResult.self, from: snapshotData),
              SearchItem(media).id == mediaID else { return nil }
        return media
    }

    var displayTitle: String {
        if let savedTitle, !savedTitle.isEmpty { return savedTitle }
        if let savedMedia { return SearchItem(savedMedia).title }
        return "Saved title — metadata unavailable"
    }

    var statusLabel: String {
        switch status {
        case LibraryStatus.watchlist.rawValue: "Watchlist"
        case LibraryStatus.watching.rawValue: "Watching"
        case LibraryStatus.watched.rawValue: "Watched"
        case "none": "No viewing status"
        default: "Unrecognized viewing status"
        }
    }

    var thumbnailURL: URL? {
        guard let savedPosterURL, let url = URL(string: savedPosterURL),
              url.scheme == "https", url.host == "image.tmdb.org", url.user == nil, url.password == nil else { return nil }
        return url
    }
}
