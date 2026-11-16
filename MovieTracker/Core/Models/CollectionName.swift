import Foundation

enum CollectionName {
    static func validated(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !value.isEmpty, value.count <= 100, value.utf8.count <= 1_024,
              !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0) }) else { throw CollectionError.invalidName }
        return value
    }
    static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum CollectionError: Error, LocalizedError {
    case invalidName, duplicateName, unavailable, invalidOrder
    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a collection name from 1 to 100 characters without control characters."
        case .duplicateName: "A collection with this name already exists. Choose another name."
        case .unavailable: "This collection is no longer available. Return to Library and try again."
        case .invalidOrder: "The collection changed. Reopen it before changing the order."
        }
    }
}
