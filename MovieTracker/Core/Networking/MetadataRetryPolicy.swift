import Foundation

/// Idempotent JSON GETs only. Long server-directed waits are surfaced, never shortened to fit a budget.
struct MetadataRetryPolicy: Sendable {
    let maximumRetries: Int
    let maximumDelay: TimeInterval
    let maximumTotalDelay: TimeInterval
    static let standard = Self(maximumRetries: 2, maximumDelay: 2, maximumTotalDelay: 3)
    static let none = Self(maximumRetries: 0, maximumDelay: 0, maximumTotalDelay: 0)

    func delay(for error: MetadataError, retries: Int, totalDelay: TimeInterval, serverDelay: TimeInterval) -> TimeInterval? {
        guard retries < max(0, maximumRetries) else { return nil }
        switch error {
        case .timedOut, .connectionLost, .connectionFailed, .dnsFailure, .rateLimited: break
        case .server(let status) where [500, 502, 503, 504].contains(status): break
        default: return nil
        }
        let delay = max(retries == 0 ? 0.5 : 1, serverDelay)
        guard delay.isFinite, delay >= 0, delay <= maximumDelay, totalDelay + delay <= maximumTotalDelay else { return nil }
        return delay
    }

    static func retryAfterSeconds(_ header: String?, at now: Date) -> TimeInterval? {
        guard let header else { return nil }
        let raw = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }), let value = TimeInterval(raw), value.isFinite { return value }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .gmt
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; formatter.isLenient = false
        guard let date = formatter.date(from: raw) else { return nil }
        let delay = date.timeIntervalSince(now)
        return delay.isFinite ? max(0, delay) : nil
    }
    static func sanitizedDelay(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let roundedUp = seconds.rounded(.up)
        return roundedUp < Double(Int.max) ? String(Int(roundedUp)) : String(format: "%.0f", roundedUp)
    }
}
