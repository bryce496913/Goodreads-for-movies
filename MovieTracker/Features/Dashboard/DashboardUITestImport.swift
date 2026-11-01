#if DEBUG
import Foundation

/// Generic fixture transport. Dataset definitions live in test targets. Never runs against a user store.
enum DashboardUITestImport {
    @MainActor static func load(into store: LibraryStore) throws {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--ui-testing-search"),
              process.arguments.contains("--ui-testing-dashboard"),
              !process.arguments.contains(where: { $0.hasPrefix("--ui-testing-library-store=") }),
              let payload = process.environment["DASHBOARD_UI_INPUT"], let data = payload.data(using: .utf8) else { return }
        let input = try JSONDecoder().decode(DashboardInput.self, from: data)
        guard store.entries.isEmpty, store.viewingEvents.isEmpty, store.episodeProgress.isEmpty else { return }
        try store.writeTransaction { context in
            for row in input.titles {
                guard let id = row.mediaID else { continue }
                let record = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: id))
                record.id = row.recordID; record.status = row.status; record.isFavorite = row.favorite
                record.savedTitle = row.title; record.savedYear = row.year; record.savedPosterURL = row.posterURL?.absoluteString
                record.addedAt = row.addedAt; record.updatedAt = row.updatedAt; record.snapshotData = row.mediaData
                record.ratingHalfStarUnits = row.ratingUnits; record.ratingUpdatedAt = row.ratingUpdatedAt
                context.insert(record)
            }
            for row in input.viewings {
                guard let id = row.mediaID,
                      let media = DiaryMedia.restore(data: row.mediaData, kind: id.kind.rawValue, value: id.value, title: row.title) else { continue }
                context.insert(try StoredViewingEvent(id: row.id, media: media, watchedDate: row.watchedDate, recordedAt: row.recordedAt))
            }
            for row in input.reviews {
                guard let id = row.mediaID,
                      let media = DiaryMedia.restore(data: nil, kind: id.kind.rawValue, value: id.value, title: row.title) else { continue }
                let review = try StoredPersonalReview(id: row.id, media: media, text: row.text, createdAt: row.createdAt, viewingEventID: nil)
                review.editedAt = row.editedAt; context.insert(review)
            }
            for row in input.seasons {
                let show = row.seriesData.flatMap { try? JSONDecoder().decode(TVShow.self, from: $0) }
                    ?? TVShow(id: row.seriesID.value, title: row.title)
                let season = try StoredTVSeason(show: show, summary: TVSeasonSummary(number: row.number, providerID: nil, name: "Season \(row.number)", episodeCount: row.expectedEpisodes))
                season.id = row.id; season.expectedRegularSeasonCount = row.expectedRegularSeasons
                season.isListed = row.listed; season.listingLoaded = row.loaded; season.episodesData = row.episodesData
                season.listedIDsData = row.listedIDsData; season.refreshedAt = row.refreshedAt; context.insert(season)
            }
            for row in input.progress {
                let episode = try JSONDecoder().decode(TVEpisode.self, from: row.episodeData)
                let progress = try StoredEpisodeProgress(episode: episode, watched: row.watched, now: row.watchedAt ?? .distantPast)
                progress.id = row.id; progress.watchedAt = row.watchedAt; context.insert(progress)
            }
        }
    }
}
#endif
