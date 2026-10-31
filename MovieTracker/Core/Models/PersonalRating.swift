import Foundation

/// Precise personal rating. Nil represents unrated; a value is always 1...10 half-stars.
struct PersonalRating: Equatable, Hashable, Sendable, Codable {
    let halfStarUnits: Int

    init(halfStarUnits: Int) throws {
        guard (1...10).contains(halfStarUnits) else { throw RatingValidationError.invalidUnits }
        self.halfStarUnits = halfStarUnits
    }

    var stars: Double { Double(halfStarUnits) / 2 }
    var label: String { String(format: "%.1f stars", stars) }
    static var allValues: [Self] { (1...10).compactMap { try? Self(halfStarUnits: $0) } }

    /// Preserve compatible legacy stars without rounding arbitrary old values into a valid rating.
    static func fromLegacyStars(_ stars: Double) throws -> Self? {
        if stars == 0 { return nil }
        let units = stars * 2
        guard stars.isFinite, (1.0...10.0).contains(units), units.rounded() == units else {
            throw RatingValidationError.invalidLegacyValue
        }
        return try Self(halfStarUnits: Int(units))
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Int.self)
        try self.init(halfStarUnits: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(halfStarUnits)
    }
}

enum RatingValidationError: Error, LocalizedError {
    case invalidUnits, invalidLegacyValue
    var errorDescription: String? {
        switch self {
        case .invalidUnits: "Choose a personal rating from 0.5 to 5.0 stars in half-star steps."
        case .invalidLegacyValue: "The saved personal rating is not on the supported scale. Choose a new rating or clear it."
        }
    }
}
