import Foundation

/// A lightweight date type storing the number of days since the Unix epoch (January 1, 1970).
/// All arithmetic (weekday, next/previous day, adding days) uses pure integer operations —
/// no Foundation Calendar needed for core operations.
public struct CalendarDate: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let daysSince1970: Int

    /// Creates a CalendarDate from year, month, day components.
    /// Returns nil if the date is invalid (e.g., February 30).
    public init?(year: Int, month: Int, day: Int) {
        guard month >= 1, month <= 12, day >= 1 else { return nil }

        let maxDay = CalendarDate.daysInMonth(year: year, month: month)
        guard day <= maxDay else { return nil }

        self.year = year
        self.month = month
        self.day = day
        self.daysSince1970 = CalendarDate.daysSinceEpoch(year: year, month: month, day: day)
    }

    /// Creates a CalendarDate from the number of days since January 1, 1970.
    public init?(daysSince1970: Int) {
        let (y, m, d) = CalendarDate.civilFromDays(daysSince1970)
        self.year = y
        self.month = m
        self.day = d
        self.daysSince1970 = daysSince1970
    }

    /// Returns today's date using the current calendar.
    public static var today: CalendarDate {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: components.year!, month: components.month!, day: components.day!)!
    }

    // MARK: - Weekday Arithmetic

    /// Returns the day of week: 1 = Sunday, 2 = Monday, ..., 7 = Saturday.
    /// Matches Foundation's `Calendar.component(.weekday)` convention.
    /// Uses pure arithmetic on `daysSince1970` — no Foundation Date conversion.
    public var weekday: Int {
        // Jan 1, 1970 = Thursday (Foundation weekday 5)
        // daysSince1970 % 7: 0=Thu, 1=Fri, 2=Sat, 3=Sun, 4=Mon, 5=Tue, 6=Wed
        let mod = ((daysSince1970 % 7) + 7) % 7 // normalize to 0-6 for negative values
        // Map mod to Foundation weekday: 0→5, 1→6, 2→7, 3→1, 4→2, 5→3, 6→4
        return (mod + 4) % 7 + 1
    }

    /// Returns true if this date falls on a weekday (Monday-Friday).
    public var isWeekday: Bool {
        let mod = ((daysSince1970 % 7) + 7) % 7
        return mod != 2 && mod != 3 // Not Saturday (2) and not Sunday (3)
    }

    /// Returns the next calendar day.
    public var nextDay: CalendarDate? {
        CalendarDate(daysSince1970: daysSince1970 + 1)
    }

    /// Returns the previous calendar day.
    public var previousDay: CalendarDate? {
        CalendarDate(daysSince1970: daysSince1970 - 1)
    }

    /// Adds a number of days to the date.
    public func addingDays(_ days: Int) -> CalendarDate? {
        CalendarDate(daysSince1970: daysSince1970 + days)
    }

    // MARK: - Comparable

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        lhs.daysSince1970 < rhs.daysSince1970
    }

    // MARK: - Foundation Bridge

    /// Converts CalendarDate to Foundation Date.
    public var date: Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    // MARK: - Pure Gregorian Arithmetic

    /// Returns the number of days in a given month.
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1: 31
        case 2: isLeapYear(year) ? 29 : 28
        case 3: 31
        case 4: 30
        case 5: 31
        case 6: 30
        case 7: 31
        case 8: 31
        case 9: 30
        case 10: 31
        case 11: 30
        case 12: 31
        default: 0
        }
    }

    /// Returns true if the given year is a leap year.
    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }

    /// Converts year/month/day to days since Unix epoch using the civil calendar algorithm.
    /// Based on Howard Hinnant's `days_from_civil` algorithm.
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        var y = year
        let m = month
        if m <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Converts days since Unix epoch back to year/month/day.
    /// Based on Howard Hinnant's `civil_from_days` algorithm.
    private static func civilFromDays(_ z: Int) -> (year: Int, month: Int, day: Int) {
        let z = z + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (y + (m <= 2 ? 1 : 0), m, d)
    }
}

// MARK: - CustomStringConvertible

extension CalendarDate: CustomStringConvertible {
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
