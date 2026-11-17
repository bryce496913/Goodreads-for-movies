import Foundation

extension DashboardAggregator {
    /// Gregorian diary values are civil UTC dates. Episode marks are instants grouped in the
    /// supplied local time zone. A status, rating edit or recordedAt never invents a watch date.
    static func personalStatistics(_ input: PersonalStatisticsInput, year: Int, now: Date,
                                   timeZone: TimeZone) throws -> PersonalStatisticsSnapshot {
        try Task.checkCancellation()
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw PersonalStatisticsError.invalidReferenceDate }
        guard (1...9999).contains(year) else { throw PersonalStatisticsError.invalidYear }
        var civil = Calendar(identifier: .gregorian); civil.timeZone = .gmt
        var local = Calendar(identifier: .gregorian); local.timeZone = timeZone
        let currentYear = local.component(.year, from: now)
        let today = DiaryDates.storageDate(from: now, timeZone: timeZone)
        var years: Set<Int> = [currentYear, year]
        var months = (1...12).map { PersonalStatisticsSnapshot.Month(number: $0) }
        var titles: [MediaID: PersonalStatisticsInput.Title] = [:]
        var metadata: [MediaID: MediaSearchResult] = [:]
        var nextExpiry: Date?
        func registerMetadata(_ data: Data?, for id: MediaID) {
            guard let data, let media = try? JSONDecoder().decode(MediaSearchResult.self, from: data),
                  SearchItem(media).id == id, MetadataPolicy.mayDisplay(media, at: now) else { return }
            if let old = metadata[id], (old.metadataRetrievedAt ?? .distantPast) >= (media.metadataRetrievedAt ?? .distantPast) { return }
            metadata[id] = media
        }
        for row in input.titles {
            try Task.checkCancellation()
            guard let id = row.mediaID else { continue }
            if let old = titles[id], old.updatedAt > row.updatedAt
                || (old.updatedAt == row.updatedAt && old.recordID.uuidString < row.recordID.uuidString) { continue }
            titles[id] = row
        }
        var ratings = (1...10).map { PersonalStatisticsSnapshot.RatingBucket(units: $0) }
        var unrated = 0, invalidRatings = 0
        for row in titles.values {
            try Task.checkCancellation()
            do {
                let rating: PersonalRating?
                if let units = row.ratingUnits { rating = try PersonalRating(halfStarUnits: units) }
                else if let legacy = row.legacyRating { rating = try PersonalRating.fromLegacyStars(legacy) }
                else { rating = nil }
                if let rating { ratings[rating.halfStarUnits - 1].count += 1 } else { unrated += 1 }
            } catch { invalidRatings += 1 }
        }
        var seenEvents = Set<UUID>(), movies = Set<MediaID>(), series = Set<MediaID>()
        var undated = 0, excluded = 0
        for event in input.viewings where seenEvents.insert(event.id).inserted {
            try Task.checkCancellation()
            guard let id = event.mediaID else { excluded += 1; continue }
            guard let date = event.watchedDate else { undated += 1; continue }
            guard date.timeIntervalSinceReferenceDate.isFinite, date <= today else { excluded += 1; continue }
            let eventYear = civil.component(.year, from: date), month = civil.component(.month, from: date)
            guard (1...9999).contains(eventYear), (1...12).contains(month) else { excluded += 1; continue }
            years.insert(eventYear)
            guard eventYear == year else { continue }
            if id.kind == .movie { months[month - 1].movieEvents += 1; movies.insert(id) }
            else { months[month - 1].seriesEvents += 1; series.insert(id) }
            registerMetadata(event.mediaData, for: id)
        }
        var progress: [EpisodeID: PersonalStatisticsInput.Episode] = [:], conflicts = Set<EpisodeID>()
        for row in input.episodes {
            try Task.checkCancellation()
            guard row.id.seriesID.kind == .tvShow else { continue }
            if let old = progress[row.id], old.watched != row.watched || old.markedAt != row.markedAt { conflicts.insert(row.id) }
            else { progress[row.id] = row }
        }
        var unknownDates = 0, excludedDates = 0, overallEpisodes = 0
        for row in progress.values where row.watched && !conflicts.contains(row.id) {
            try Task.checkCancellation()
            overallEpisodes += 1
            guard let date = row.markedAt else { unknownDates += 1; continue }
            guard date.timeIntervalSinceReferenceDate.isFinite, date <= now else { excludedDates += 1; continue }
            let markedYear = local.component(.year, from: date), month = local.component(.month, from: date)
            guard (1...9999).contains(markedYear), (1...12).contains(month) else { excludedDates += 1; continue }
            years.insert(markedYear)
            if markedYear == year { months[month - 1].episodeMarks += 1 }
        }
        var genreTitles: [String: Set<MediaID>] = [:], genreNames: [String: String] = [:], missingGenres = 0
        let watchedTitles = movies.union(series)
        for id in watchedTitles {
            try Task.checkCancellation()
            registerMetadata(titles[id]?.mediaData, for: id)
            guard let media = metadata[id] else { missingGenres += 1; continue }
            let genres: [MediaGenre]
            switch media { case .movie(let value): genres = value.genres; case .tvShow(let value): genres = value.genres }
            let valid = genres.filter { !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !valid.isEmpty else { missingGenres += 1; continue }
            if MetadataPolicy.isTMDB(id), let receipt = media.metadataRetrievedAt {
                let expiry = receipt.addingTimeInterval(MetadataPolicy.retention)
                nextExpiry = min(nextExpiry ?? expiry, expiry)
            }
            // Provider namespace + genre ID preserve ownership. Media kind stays in each title ID.
            let namespace = id.value.split(separator: ":").first.map(String.init) ?? id.value
            for genre in valid {
                let key = namespace + ":" + genre.id
                genreTitles[key, default: []].insert(id)
                if genreNames[key] == nil || genre.name < genreNames[key]! { genreNames[key] = genre.name }
            }
        }
        let genres = try genreTitles.map { key, values -> PersonalStatisticsSnapshot.Genre in
            try Task.checkCancellation()
            return .init(id: key, name: genreNames[key] ?? "", titles: values.count)
        }.sorted {
            if $0.titles != $1.titles { return $0.titles > $1.titles }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
        try Task.checkCancellation()
        return PersonalStatisticsSnapshot(year: year, years: years.sorted(by: >), months: months,
            uniqueMovies: movies.count, uniqueSeries: series.count, ratingBuckets: ratings,
            unratedTitles: unrated, invalidRatings: invalidRatings, genres: genres,
            genreEligibleTitles: watchedTitles.count - missingGenres, missingGenreTitles: missingGenres,
            nextMetadataExpiry: nextExpiry, undatedEvents: undated, excludedEvents: excluded,
            unknownEpisodeDates: unknownDates, excludedEpisodeDates: excludedDates,
            overallWatchedEpisodes: overallEpisodes, conflictingEpisodes: conflicts.count)
    }
}
