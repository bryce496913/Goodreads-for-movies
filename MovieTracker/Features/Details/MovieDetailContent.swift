import SwiftUI

struct MovieDetailContent: View {
    let movie: Movie
    var body: some View {
        DetailFacts(title: "Movie information", facts: [
            DetailFact(label: "Released", value: DetailFormatting.date(movie.releaseDate)),
            DetailFact(label: "Runtime", value: DetailFormatting.runtime(movie.runtimeMinutes))
        ])
        DetailGenres(genres: movie.genres)
        DetailSynopsis(overview: movie.overview)
    }
}
