import Foundation

struct TMDBCredits: Decodable, Sendable {
    let cast: [Person]

    struct Person: Decodable, Sendable {
        let id: Int?
        let name: String?
        let character: String?
        let order: Int?
    }

    func preview() -> [CastMember] {
        var seen = Set<Int>()
        return cast.sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }.compactMap { person -> CastMember? in
            guard let id = person.id, id > 0, let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, seen.insert(id).inserted else { return nil }
            let character = person.character?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CastMember(id: "tmdb:\(id)", name: name, character: character?.isEmpty == false ? character : nil)
        }.prefix(10).map { $0 }
    }
}
