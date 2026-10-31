import Foundation

enum DiaryDates {
    /// Keep a date-only watch stable across timezones. Recorded timestamps remain full instants.
    static func storageDate(from pickerDate: Date, timeZone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return utc.date(from: local.dateComponents([.year, .month, .day], from: pickerDate)) ?? pickerDate
    }
    static func pickerDate(from stored: Date, timeZone: TimeZone = .current) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        return local.date(from: utc.dateComponents([.year, .month, .day], from: stored)) ?? stored
    }
}
