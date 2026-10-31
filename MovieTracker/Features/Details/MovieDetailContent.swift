import SwiftUI

struct MovieDetailContent: View {
    let movie: Movie
    let resolver: MetadataImageResolver?
    var body: some View {
        DetailArtworkHeader(item: SearchItem(.movie(movie)), backdropReference: movie.backdropReference, resolver: resolver)
        DetailFacts(title: "Movie information", facts: [
            DetailFact(label: "Released", value: DetailFormatting.date(movie.releaseDate)),
            DetailFact(label: "Runtime", value: DetailFormatting.runtime(movie.runtimeMinutes))
        ])
        DetailGenres(genres: movie.genres)
        DetailSynopsis(overview: movie.overview)
    }
}
