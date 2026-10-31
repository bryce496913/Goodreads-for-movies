import SwiftUI

struct TVDetailContent: View {
    let show: TVShow
    var body: some View {
        DetailFacts(title: "Series information", facts: [
            DetailFact(label: "First aired", value: DetailFormatting.date(show.firstAirDate)),
            DetailFact(label: "Series status", value: show.seriesStatus?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? show.seriesStatus ?? "Unavailable" : "Unavailable"),
            DetailFact(label: "Episode runtime", value: DetailFormatting.runtime(show.episodeRuntimeMinutes))
        ])
        DetailGenres(genres: show.genres)
        DetailSynopsis(overview: show.overview)
        DetailFacts(title: "Season summary", facts: [
            DetailFact(label: "Seasons", value: DetailFormatting.count(show.seasonCount)),
            DetailFact(label: "Episodes", value: DetailFormatting.count(show.episodeCount))
        ])
        Text("Season and episode information is a summary. Episode tracking is not available yet.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
