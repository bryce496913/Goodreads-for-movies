import SwiftUI

struct DetailSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            SectionHeading(title: title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailGenres: View {
    let genres: [MediaGenre]
    var body: some View {
        DetailSection(title: "Genres") {
            if genres.isEmpty {
                Text("Genre information unavailable.").foregroundStyle(.secondary)
            } else {
                // Text can wrap vertically, including at accessibility sizes.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading) {
                    ForEach(genres, id: \.id) { genre in
                        Text(genre.name)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(AppStyle.Spacing.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct DetailSynopsis: View {
    let overview: String
    var body: some View {
        DetailSection(title: "Synopsis") {
            Text(overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No synopsis available." : overview)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("details.synopsis")
        }
    }
}

struct DetailFact: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct DetailFacts: View {
    let title: String
    let facts: [DetailFact]
    var body: some View {
        DetailSection(title: title) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.label).font(.subheadline).foregroundStyle(.secondary)
                    Text(fact.value).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("details.fact.\(fact.label)")
            }
        }
    }
}

struct DetailCast: View {
    let members: [CastMember]
    let isLoading: Bool
    let unavailable: Bool
    var body: some View {
        DetailSection(title: "Cast") {
            if isLoading && members.isEmpty {
                ProgressView("Loading cast…")
            } else {
                if unavailable { Text("Cast could not be updated.").foregroundStyle(.secondary) }
                if members.isEmpty {
                    Text("No cast information available.").foregroundStyle(.secondary)
                } else {
                    ForEach(members) { member in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.name).font(.headline)
                            Text(member.character?.isEmpty == false ? member.character ?? "Role unavailable" : "Role unavailable")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("details.cast.\(member.id)")
                    }
                }
            }
        }
    }
}

enum DetailFormatting {
    static func date(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func count(_ value: Int?) -> String {
        guard let value, value > 0 else { return "Unavailable" }
        return String(value)
    }

    static func runtime(_ value: Int?) -> String {
        guard let value, value > 0 else { return "Unavailable" }
        return "\(value) min"
    }
}
