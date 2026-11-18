/// Public documentation has not established this app's durable/offline artwork rights.
/// See docs/ARTWORK_LICENSING_GATE.md and docs/ARTWORK_METADATA_RELIABILITY.md.
/// No runtime setting or test flag can authorize persistent storage.
enum ProviderArtworkPolicy {
    static let persistentStorageAuthorized = false
    static let memoryEntries = 40
    static let memoryBytes = 40_000_000
    static let maximumResponseBytes = 2_000_000
    static let maximumPixelDimension = 2_048
    static let settingsExplanation = "Artwork is kept only in bounded memory. Offline artwork after relaunch is unavailable while persistent-storage rights remain unconfirmed. Clearing temporary artwork preserves your personal data and saved text."
}
