import Foundation

/// Read-only deterministic aggregation. No context, network, analytics SDK or persistence mutation.
enum DashboardAggregator {
    static func aggregate(_ input: DashboardInput, now: Date = .now) throws -> DashboardSnapshot {
        try Task.checkCancellation()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let today = calendar.startOfDay(for: now)
        var canonical: [MediaID: DashboardInput.Title] = [:]
        var seenRows = Set<UUID>(), legacyReviews = 0, unclassified = 0, duplicates = 0
        for row in input.titles where seenRows.insert(row.recordID).inserted {
            try Task.checkCancellation()
            if row.legacyReview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { legacyReviews += 1 }
            guard let id = row.mediaID else { unclassified += 1; continue }
            if let old = canonical[id] {
                duplicates += 1
                if row.updatedAt < old.updatedAt || (row.updatedAt == old.updatedAt && row.recordID.uuidString > old.recordID.uuidString) { continue }
            }
            canonical[id] = row
        }
        var titles: [MediaID: DashboardTitle] = [:]
        var ratingSum = 0, ratingCount = 0, invalidRatings = 0
        for (id, row) in canonical {
            try Task.checkCancellation()
            let rating: PersonalRating?
            do {
                if let units = row.ratingUnits { rating = try PersonalRating(halfStarUnits: units) }
                else if let stars = row.legacyRating { rating = try PersonalRating.fromLegacyStars(stars) }
                else { rating = nil }
            } catch { rating = nil; invalidRatings += 1 }
            if let rating { ratingSum += rating.halfStarUnits; ratingCount += 1 }
            let media = row.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? nil : decodeMedia(row.mediaData)
            titles[id] = DashboardTitle(id: id, title: row.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? row.title ?? "Saved title" : media.map { SearchItem($0).title } ?? "Saved title — metadata unavailable",
                year: row.year, posterURL: row.posterURL, rating: rating)
        }
        func title(_ id: MediaID, fallback: String) -> DashboardTitle {
            titles[id] ?? DashboardTitle(id: id, title: fallback, year: nil, posterURL: nil, rating: nil)
        }
        var seenEvents = Set<UUID>()
        let diary = input.viewings.filter { seenEvents.insert($0.id).inserted }.compactMap { event -> DashboardDiaryItem? in
            guard let id = event.mediaID else { return nil }
            return DashboardDiaryItem(id: event.id, title: title(id, fallback: event.title), watchedDate: event.watchedDate, recordedAt: event.recordedAt)
        }.sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt > rhs.recordedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var watchedMovies = Set(canonical.filter { $0.key.kind == .movie && $0.value.status == "watched" }.map(\.key))
        for event in diary where event.title.id.kind == .movie && (event.watchedDate == nil || event.watchedDate.map { $0 <= today } == true) {
            watchedMovies.insert(event.title.id)
        }
        var seenReviewIDs = Set<UUID>()
        let reviews = input.reviews.filter { seenReviewIDs.insert($0.id).inserted && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var progress: [EpisodeID: DashboardInput.Progress] = [:]
        for value in input.progress where value.episodeID.seriesID.kind == .tvShow {
            try Task.checkCancellation()
            if let old = progress[value.episodeID] {
                if (value.watchedAt ?? .distantPast) < (old.watchedAt ?? .distantPast)
                    || (value.watchedAt == old.watchedAt && value.id.uuidString > old.id.uuidString) { continue }
            }
            progress[value.episodeID] = value
        }
        let watched = progress.values.filter(\.watched)
        let watchedIDs = Set(watched.map(\.episodeID))
        let seriesIDs = Set(watched.map { $0.episodeID.seriesID }.filter { $0.kind == .tvShow })
        var cached: [MediaID: [Int: DashboardInput.Season]] = [:]
        for row in input.seasons {
            if let old = cached[row.seriesID]?[row.number] {
                if (old.refreshedAt ?? .distantPast) > (row.refreshedAt ?? .distantPast)
                    || (old.refreshedAt == row.refreshedAt && old.id.uuidString < row.id.uuidString) { continue }
            }
            cached[row.seriesID, default: [:]][row.number] = row
        }
        let progressBySeries = Dictionary(grouping: progress.values, by: { $0.episodeID.seriesID })
        let watchedBySeries = Dictionary(grouping: watched, by: { $0.episodeID.seriesID })
        var continuing: [ContinueWatchingItem] = []
        for id in seriesIDs {
            try Task.checkCancellation()
            let regular = Array(cached[id, default: [:]].values).filter { $0.number > 0 }.sorted { $0.number < $1.number }
            var episodes: [EpisodeID: TVEpisode] = [:]
            var complete = !regular.isEmpty && regular.compactMap(\.expectedRegularSeasons).max() == regular.count
            for season in regular {
                let values = decode([TVEpisode].self, season.episodesData) ?? []
                let listed = Set(decode([EpisodeID].self, season.listedIDsData) ?? [])
                complete = complete && season.listed && season.loaded && season.expectedEpisodes == values.count
                    && Set(values.map(\.id)).count == values.count && listed == Set(values.map(\.id))
                let valid = values.filter { $0.id.seriesID == id && $0.seasonNumber == season.number }
                complete = complete && valid.count == values.count
                for episode in valid { episodes[episode.id] = episode }
            }
            for row in progressBySeries[id, default: []] where row.season > 0 {
                if let episode = decode(TVEpisode.self, row.episodeData), episodes[row.episodeID] == nil {
                    complete = false; episodes[row.episodeID] = episode
                }
            }
            let values = Array(episodes.values)
            let summary = EpisodeProgressSummary.calculate(episodes: values, watchedIDs: watchedIDs, coverageKnown: complete, now: now)
            let remaining = values.filter { !watchedIDs.contains($0.id) }
            let available = remaining.filter { $0.airDate.map { $0 <= today } == true }.sorted(by: episodeOrder)
            let unknown = remaining.contains { $0.airDate == nil }
            guard !available.isEmpty || !complete || unknown else { continue } // Nothing aired remains: never recommend a future episode.
            let next = complete && !unknown ? available.first : nil
            let last = watchedBySeries[id, default: []].filter { $0.watchedAt != nil }.sorted {
                if $0.watchedAt != $1.watchedAt { return ($0.watchedAt ?? .distantPast) > ($1.watchedAt ?? .distantPast) }
                return $0.episodeID.providerValue < $1.episodeID.providerValue
            }.first
            let seasons = Array(cached[id, default: [:]].values).sorted { $0.number < $1.number }
            let savedShow = seasons.compactMap { decode(TVShow.self, $0.seriesData) }.first { $0.id == id }
            let fallback = seasons.first?.title ?? "Saved series — metadata unavailable"
            let show = savedShow ?? TVShow(id: id.value, title: titles[id]?.title ?? fallback)
            continuing.append(ContinueWatchingItem(title: title(id, fallback: show.title), show: show, progress: summary,
                next: next, lastMarked: last.flatMap { decode(TVEpisode.self, $0.episodeData) }, lastMarkedAt: last?.watchedAt))
        }
        continuing.sort {
            if $0.lastMarkedAt != $1.lastMarkedAt { return ($0.lastMarkedAt ?? .distantPast) > ($1.lastMarkedAt ?? .distantPast) }
            return mediaKey($0.id) < mediaKey($1.id)
        }
        var activity = diary.map { DashboardActivity(id: "viewing:\($0.id.uuidString)", title: $0.title, label: "Viewing recorded", date: $0.recordedAt, watchedDate: $0.watchedDate) }
        activity += reviews.compactMap { review in
            guard let id = review.mediaID else { return nil }
            let label = review.editedAt != review.createdAt ? "Review edited" : (review.imported ? "Review imported" : "Review written")
            return DashboardActivity(id: "review:\(review.id.uuidString)", title: title(id, fallback: review.title), label: label, date: review.editedAt, watchedDate: nil)
        }
        activity += canonical.compactMap { id, row in
            guard let date = row.ratingUpdatedAt, let item = titles[id] else { return nil }
            if row.ratingUnits == nil && row.legacyRating == nil {
                return DashboardActivity(id: "rating:\(mediaKey(id))", title: item, label: "Personal rating cleared", date: date, watchedDate: nil)
            }
            guard let rating = item.rating else { return nil }
            return DashboardActivity(id: "rating:\(mediaKey(id))", title: item, label: "Personal rating updated: \(rating.label)", date: date, watchedDate: nil)
        }
        activity.sort { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        let watchlist = canonical.filter { $0.value.status == "watchlist" }.sorted {
            $0.value.addedAt != $1.value.addedAt ? $0.value.addedAt > $1.value.addedAt : mediaKey($0.key) < mediaKey($1.key)
        }.compactMap { titles[$0.key] }
        let recentWatched = diary.filter { $0.watchedDate.map { $0 <= today } == true }
        let stats = ViewingStatistics(watchedMovies: watchedMovies.count, seriesWithProgress: seriesIDs.count,
            watchedEpisodes: watched.count, watchlist: watchlist.count, favorites: canonical.values.filter(\.favorite).count,
            ratings: ratingCount, averageRating: ratingCount == 0 ? nil : Double(ratingSum) / Double(ratingCount) / 2,
            reviews: reviews.count + legacyReviews, viewingEvents: seenEvents.count)
        try Task.checkCancellation()
        return DashboardSnapshot(statistics: stats, continueWatching: Array(continuing.prefix(5)),
            recentlyWatched: Array(recentWatched.prefix(5)), recentDiary: Array(diary.prefix(5)), watchlist: Array(watchlist.prefix(5)),
            activity: Array(activity.prefix(8)), duplicateTitles: duplicates, invalidRatings: invalidRatings, unclassifiedTitles: unclassified,
            hasPersonalData: !input.titles.isEmpty || !input.viewings.isEmpty || !input.reviews.isEmpty || !watched.isEmpty)
    }
    private static func decodeMedia(_ data: Data?) -> MediaSearchResult? { decode(MediaSearchResult.self, data) }
    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }; return try? JSONDecoder().decode(type, from: data)
    }
    private static func mediaKey(_ id: MediaID) -> String { id.kind.rawValue + ":" + id.value }
    private static func episodeOrder(_ lhs: TVEpisode, _ rhs: TVEpisode) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber { return lhs.seasonNumber < rhs.seasonNumber }
        if lhs.number != rhs.number { return lhs.number < rhs.number }
        return lhs.id.providerValue < rhs.id.providerValue
    }
}
