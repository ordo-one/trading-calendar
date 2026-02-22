import Foundation

// MARK: - Market Closure Rule Types

/// Represents a rule for calculating market closure dates across any year.
/// Clients can compose these rules to define custom exchange calendars.
public enum MarketClosureRule: Sendable {
    /// Fixed date closure (e.g., Christmas on Dec 25)
    case fixed(month: Int, day: Int, name: String)

    /// Nth weekday of month (e.g., 3rd Monday of January)
    case nthWeekday(month: Int, nth: Int, weekday: Int, name: String)

    /// Last weekday of month (e.g., last Monday of May)
    case lastWeekday(month: Int, weekday: Int, name: String)

    /// Day after nth weekday (e.g., day after 4th Thursday of November)
    case dayAfterNthWeekday(month: Int, nth: Int, weekday: Int, name: String)

    /// Market closure relative to Easter (e.g., Good Friday = Easter - 2 days)
    case easterOffset(days: Int, name: String)

    /// Swedish Midsummer (Friday between June 19-25)
    case midsummer(name: String)

    /// Canadian Victoria Day (Monday on or before May 24)
    case victoriaDay(name: String)

    /// Christmas and Boxing Day with cascading substitutes (when both fall on weekend)
    /// Used by Canada, UK, Australia, etc.
    case christmasBoxingDayCascade

    /// One-off closure for a specific year (e.g., Euronext Paris Dec 31, 2015)
    case oneOff(year: Int, month: Int, day: Int, name: String)

    /// Fixed date with automatic bridge day (Monday off if Tue, Friday off if Thu)
    /// Used by Hungarian market and similar
    case fixedWithBridge(month: Int, day: Int, name: String)

    /// Fixed date with US-style observed day (Sat->Fri, Sun->Mon)
    case fixedWithObserved(month: Int, day: Int, name: String)

    /// Fixed date with UK-style substitute (weekend->next working day)
    case fixedWithSubstitute(month: Int, day: Int, name: String)

    /// Orthodox Easter offset (uses Julian calendar calculation)
    case orthodoxEasterOffset(days: Int, name: String)

    /// Easter offset that only applies until a specific year (inclusive)
    case easterOffsetUntilYear(days: Int, untilYear: Int, name: String)

    /// Easter offset that only applies from a specific year (inclusive)
    case easterOffsetFromYear(days: Int, fromYear: Int, name: String)

    /// Fixed date with US-style observed, starting from a specific year
    case fixedWithObservedFromYear(month: Int, day: Int, fromYear: Int, name: String)

    /// Japanese Vernal Equinox (around March 20-21, astronomically calculated)
    case japaneseVernalEquinox(name: String)

    /// Japanese Autumnal Equinox (around September 22-23, astronomically calculated)
    case japaneseAutumnalEquinox(name: String)

    /// Fixed date with Japanese substitute (Sunday only -> Monday, Saturday stays on Saturday which is already closed)
    case fixedWithJapaneseSubstitute(month: Int, day: Int, name: String)

    /// Returns the name of this market closure
    public var name: String {
        switch self {
        case let .fixed(_, _, name),
             let .nthWeekday(_, _, _, name),
             let .lastWeekday(_, _, name),
             let .dayAfterNthWeekday(_, _, _, name),
             let .easterOffset(_, name),
             let .midsummer(name),
             let .victoriaDay(name),
             let .oneOff(_, _, _, name),
             let .fixedWithBridge(_, _, name),
             let .fixedWithObserved(_, _, name),
             let .fixedWithSubstitute(_, _, name),
             let .orthodoxEasterOffset(_, name),
             let .easterOffsetUntilYear(_, _, name),
             let .easterOffsetFromYear(_, _, name),
             let .fixedWithObservedFromYear(_, _, _, name),
             let .japaneseVernalEquinox(name),
             let .japaneseAutumnalEquinox(name),
             let .fixedWithJapaneseSubstitute(_, _, name):
            return name
        case .christmasBoxingDayCascade:
            return "Christmas/Boxing Day"
        }
    }

    /// Checks if this rule matches the given date
    func matches(_ date: CalendarDate, preCalculatedEaster: CalendarDate? = nil) -> Bool {
        switch self {
        case let .fixed(month, day, _):
            return date.month == month && date.day == day

        case let .nthWeekday(month, nth, weekday, _):
            return MarketClosureRule.isNthWeekdayOfMonth(date, month: month, nth: nth, weekday: weekday)

        case let .lastWeekday(month, weekday, _):
            return MarketClosureRule.isLastWeekdayOfMonth(date, month: month, weekday: weekday)

        case let .dayAfterNthWeekday(month, nth, weekday, _):
            guard let nthDate = MarketClosureRule.findNthWeekdayOfMonth(year: date.year, month: month, nth: nth, weekday: weekday),
                  let dayAfter = nthDate.nextDay
            else {
                return false
            }
            return date == dayAfter

        case let .easterOffset(days, _):
            let easter = preCalculatedEaster ?? MarketClosureRule.calculateEaster(year: date.year)
            guard let easterDate = easter else { return false }
            guard let offsetDate = easterDate.addingDays(days) else { return false }
            return date == offsetDate

        case .midsummer:
            return MarketClosureRule.isMidsummer(date)

        case .victoriaDay:
            return MarketClosureRule.isVictoriaDay(date)

        case .christmasBoxingDayCascade:
            return MarketClosureRule.isChristmasBoxingDayClosure(date)

        case let .oneOff(year, month, day, _):
            return date.year == year && date.month == month && date.day == day

        case let .fixedWithBridge(month, day, _):
            // Check if date matches the holiday itself
            if date.month == month && date.day == day {
                return true
            }
            // Check if date is a bridge day
            guard let holidayDate = CalendarDate(year: date.year, month: month, day: day) else { return false }
            let holidayWeekday = holidayDate.weekday
            // Tuesday (3) -> Monday bridge, Thursday (5) -> Friday bridge
            if holidayWeekday == 3, let bridge = holidayDate.addingDays(-1) {
                return date == bridge
            } else if holidayWeekday == 5, let bridge = holidayDate.addingDays(1) {
                return date == bridge
            }
            return false

        case let .fixedWithObserved(month, day, _):
            // US-style: observed day when weekend, actual day otherwise
            guard let holidayDate = CalendarDate(year: date.year, month: month, day: day) else { return false }
            let weekday = holidayDate.weekday
            if weekday == 7, let observed = holidayDate.addingDays(-1) { // Saturday -> Friday
                return date == observed
            } else if weekday == 1, let observed = holidayDate.addingDays(1) { // Sunday -> Monday
                return date == observed
            }
            return date.month == month && date.day == day // Weekday - match actual date

        case let .fixedWithSubstitute(month, day, _):
            // UK-style: substitute day when weekend, actual day otherwise
            guard let holidayDate = CalendarDate(year: date.year, month: month, day: day) else { return false }
            let weekday = holidayDate.weekday
            if weekday == 7, let substitute = holidayDate.addingDays(2) { // Saturday -> Monday
                return date == substitute
            } else if weekday == 1, let substitute = holidayDate.addingDays(1) { // Sunday -> Monday
                return date == substitute
            }
            return date.month == month && date.day == day // Weekday - match actual date

        case let .orthodoxEasterOffset(days, _):
            guard let orthodoxEaster = MarketClosureRule.calculateOrthodoxEaster(year: date.year),
                  let offsetDate = orthodoxEaster.addingDays(days) else { return false }
            return date == offsetDate

        case let .easterOffsetUntilYear(days, untilYear, _):
            guard date.year <= untilYear else { return false }
            let easter = preCalculatedEaster ?? MarketClosureRule.calculateEaster(year: date.year)
            guard let easterDate = easter, let offsetDate = easterDate.addingDays(days) else { return false }
            return date == offsetDate

        case let .easterOffsetFromYear(days, fromYear, _):
            guard date.year >= fromYear else { return false }
            let easter = preCalculatedEaster ?? MarketClosureRule.calculateEaster(year: date.year)
            guard let easterDate = easter, let offsetDate = easterDate.addingDays(days) else { return false }
            return date == offsetDate

        case let .fixedWithObservedFromYear(month, day, fromYear, _):
            guard date.year >= fromYear else { return false }
            guard let holidayDate = CalendarDate(year: date.year, month: month, day: day) else { return false }
            let weekday = holidayDate.weekday
            if weekday == 7, let observed = holidayDate.addingDays(-1) {
                return date == observed
            } else if weekday == 1, let observed = holidayDate.addingDays(1) {
                return date == observed
            }
            return date.month == month && date.day == day

        case .japaneseVernalEquinox:
            let equinoxDay = MarketClosureRule.calculateVernalEquinoxDay(year: date.year)
            guard let equinoxDate = CalendarDate(year: date.year, month: 3, day: equinoxDay) else { return false }
            let weekday = equinoxDate.weekday
            // Japan substitute: Sunday -> Monday
            if weekday == 1, let substitute = equinoxDate.addingDays(1) {
                return date == substitute || date == equinoxDate
            }
            return date == equinoxDate

        case .japaneseAutumnalEquinox:
            let equinoxDay = MarketClosureRule.calculateAutumnalEquinoxDay(year: date.year)
            guard let equinoxDate = CalendarDate(year: date.year, month: 9, day: equinoxDay) else { return false }
            let weekday = equinoxDate.weekday
            // Japan substitute: Sunday -> Monday
            if weekday == 1, let substitute = equinoxDate.addingDays(1) {
                return date == substitute || date == equinoxDate
            }
            return date == equinoxDate

        case let .fixedWithJapaneseSubstitute(month, day, _):
            // Japan only substitutes Sunday -> Monday (not Saturday)
            guard let holidayDate = CalendarDate(year: date.year, month: month, day: day) else { return false }
            let weekday = holidayDate.weekday
            if weekday == 1, let substitute = holidayDate.addingDays(1) {
                return date == substitute
            }
            return date.month == month && date.day == day
        }
    }

    /// Directly calculates the date(s) for this market closure rule in a given year
    func calculateDates(for year: Int, preCalculatedEaster: CalendarDate?) -> [CalendarDate]? {
        switch self {
        case let .fixed(month, day, _):
            return [CalendarDate(year: year, month: month, day: day)].compactMap(\.self)

        case let .nthWeekday(month, nth, weekday, _):
            guard let date = MarketClosureRule.findNthWeekdayOfMonth(year: year, month: month, nth: nth, weekday: weekday) else {
                return nil
            }
            return [date]

        case let .lastWeekday(month, weekday, _):
            guard let date = MarketClosureRule.findLastWeekdayOfMonth(year: year, month: month, weekday: weekday) else {
                return nil
            }
            return [date]

        case let .dayAfterNthWeekday(month, nth, weekday, _):
            guard let nthDate = MarketClosureRule.findNthWeekdayOfMonth(year: year, month: month, nth: nth, weekday: weekday),
                  let dayAfter = nthDate.nextDay
            else {
                return nil
            }
            return [dayAfter]

        case let .easterOffset(days, _):
            guard let easter = preCalculatedEaster,
                  let offsetDate = easter.addingDays(days)
            else {
                return nil
            }
            return [offsetDate]

        case .midsummer:
            // Find Friday between June 19-25
            for day in 19 ... 25 {
                guard let date = CalendarDate(year: year, month: 6, day: day) else { continue }
                if MarketClosureRule.isMidsummer(date) {
                    return [date]
                }
            }
            return nil

        case .victoriaDay:
            // Find Monday on or before May 24 (between May 18-24)
            for day in (18 ... 24).reversed() {
                guard let date = CalendarDate(year: year, month: 5, day: day) else { continue }
                if MarketClosureRule.isVictoriaDay(date) {
                    return [date]
                }
            }
            return nil

        case .christmasBoxingDayCascade:
            return MarketClosureRule.calculateChristmasBoxingDayClosures(for: year)

        case let .oneOff(oneOffYear, month, day, _):
            // Only return the date if we're calculating for that specific year
            guard year == oneOffYear else { return nil }
            return [CalendarDate(year: year, month: month, day: day)].compactMap(\.self)

        case let .fixedWithBridge(month, day, _):
            guard let holidayDate = CalendarDate(year: year, month: month, day: day) else { return nil }
            var dates = [holidayDate]
            let holidayWeekday = holidayDate.weekday
            // Tuesday (3) -> Monday bridge, Thursday (5) -> Friday bridge
            if holidayWeekday == 3, let bridge = holidayDate.addingDays(-1) {
                dates.append(bridge)
            } else if holidayWeekday == 5, let bridge = holidayDate.addingDays(1) {
                dates.append(bridge)
            }
            return dates

        case let .fixedWithObserved(month, day, _):
            guard let holidayDate = CalendarDate(year: year, month: month, day: day) else { return nil }
            let weekday = holidayDate.weekday
            // US-style: Saturday -> Friday, Sunday -> Monday
            if weekday == 7, let observed = holidayDate.addingDays(-1) {
                return [observed]
            } else if weekday == 1, let observed = holidayDate.addingDays(1) {
                return [observed]
            }
            return [holidayDate]

        case let .fixedWithSubstitute(month, day, _):
            guard let holidayDate = CalendarDate(year: year, month: month, day: day) else { return nil }
            let weekday = holidayDate.weekday
            // UK-style: weekend -> next Monday
            if weekday == 7, let substitute = holidayDate.addingDays(2) {
                return [substitute]
            } else if weekday == 1, let substitute = holidayDate.addingDays(1) {
                return [substitute]
            }
            return [holidayDate]

        case let .orthodoxEasterOffset(days, _):
            guard let orthodoxEaster = MarketClosureRule.calculateOrthodoxEaster(year: year),
                  let offsetDate = orthodoxEaster.addingDays(days) else { return nil }
            return [offsetDate]

        case let .easterOffsetUntilYear(days, untilYear, _):
            guard year <= untilYear else { return nil }
            guard let easter = preCalculatedEaster,
                  let offsetDate = easter.addingDays(days) else { return nil }
            return [offsetDate]

        case let .easterOffsetFromYear(days, fromYear, _):
            guard year >= fromYear else { return nil }
            guard let easter = preCalculatedEaster,
                  let offsetDate = easter.addingDays(days) else { return nil }
            return [offsetDate]

        case let .fixedWithObservedFromYear(month, day, fromYear, _):
            guard year >= fromYear else { return nil }
            guard let holidayDate = CalendarDate(year: year, month: month, day: day) else { return nil }
            let weekday = holidayDate.weekday
            if weekday == 7, let observed = holidayDate.addingDays(-1) {
                return [observed]
            } else if weekday == 1, let observed = holidayDate.addingDays(1) {
                return [observed]
            }
            return [holidayDate]

        case .japaneseVernalEquinox:
            let equinoxDay = MarketClosureRule.calculateVernalEquinoxDay(year: year)
            guard let equinoxDate = CalendarDate(year: year, month: 3, day: equinoxDay) else { return nil }
            let weekday = equinoxDate.weekday
            if weekday == 1, let substitute = equinoxDate.addingDays(1) {
                return [substitute]
            }
            return [equinoxDate]

        case .japaneseAutumnalEquinox:
            let equinoxDay = MarketClosureRule.calculateAutumnalEquinoxDay(year: year)
            guard let equinoxDate = CalendarDate(year: year, month: 9, day: equinoxDay) else { return nil }
            let weekday = equinoxDate.weekday
            if weekday == 1, let substitute = equinoxDate.addingDays(1) {
                return [substitute]
            }
            return [equinoxDate]

        case let .fixedWithJapaneseSubstitute(month, day, _):
            guard let holidayDate = CalendarDate(year: year, month: month, day: day) else { return nil }
            let weekday = holidayDate.weekday
            if weekday == 1, let substitute = holidayDate.addingDays(1) {
                return [substitute]
            }
            return [holidayDate]
        }
    }
}

// MARK: - Market Closure Calculation Helpers

extension MarketClosureRule {
    /// Checks if date is the nth occurrence of a weekday in a month
    static func isNthWeekdayOfMonth(_ date: CalendarDate, month: Int, nth: Int, weekday: Int) -> Bool {
        guard date.month == month else { return false }
        guard date.weekday == weekday else { return false }
        // The nth occurrence of any weekday falls in the day range [7*(nth-1)+1, 7*nth]
        return date.day >= 7 * (nth - 1) + 1 && date.day <= 7 * nth
    }

    /// Checks if date is the last occurrence of a weekday in a month
    static func isLastWeekdayOfMonth(_ date: CalendarDate, month: Int, weekday: Int) -> Bool {
        guard date.month == month else { return false }
        guard date.weekday == weekday else { return false }
        // If adding 7 days stays in the same month, this isn't the last occurrence
        return date.day + 7 > 31 || CalendarDate(year: date.year, month: month, day: date.day + 7) == nil
    }

    /// Finds the nth weekday of a specific month
    static func findNthWeekdayOfMonth(year: Int, month: Int, nth: Int, weekday: Int) -> CalendarDate? {
        guard let firstOfMonth = CalendarDate(year: year, month: month, day: 1) else { return nil }
        let firstWeekday = firstOfMonth.weekday
        // Calculate offset to first occurrence of target weekday
        var offset = weekday - firstWeekday
        if offset < 0 { offset += 7 }
        let targetDay = 1 + offset + 7 * (nth - 1)
        return CalendarDate(year: year, month: month, day: targetDay)
    }

    /// Finds the last weekday of a specific month
    static func findLastWeekdayOfMonth(year: Int, month: Int, weekday: Int) -> CalendarDate? {
        // Start from the end of the month and work backwards
        for day in (1 ... 31).reversed() {
            guard let date = CalendarDate(year: year, month: month, day: day) else { continue }
            if date.weekday == weekday {
                return date
            }
        }
        return nil
    }

    // swiftlint:disable identifier_name

    /// Calculates Easter Sunday for a given year using the Computus algorithm
    public static func calculateEaster(year: Int) -> CalendarDate? {
        // Anonymous Gregorian algorithm
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1

        return CalendarDate(year: year, month: month, day: day)
    }

    // swiftlint:enable identifier_name

    // swiftlint:disable identifier_name

    /// Calculates Orthodox Easter Sunday for a given year using the Julian calendar
    /// Orthodox Easter follows the Julian calendar calculation, then converts to Gregorian
    static func calculateOrthodoxEaster(year: Int) -> CalendarDate? {
        // Julian calendar Easter calculation (Meeus Julian algorithm)
        let a = year % 4
        let b = year % 7
        let c = year % 19
        let d = (19 * c + 15) % 30
        let e = (2 * a + 4 * b - d + 34) % 7
        let month = (d + e + 114) / 31 // Will be 3 (March) or 4 (April)
        let day = ((d + e + 114) % 31) + 1

        // Convert Julian date to Gregorian by adding the century offset
        // For 1900-2099, the offset is 13 days
        // For 2100-2199, it will be 14 days
        let centuryOffset = 13 // Valid for 1900-2099

        // Create the Julian date, then add the offset
        guard let julianDate = CalendarDate(year: year, month: month, day: day) else {
            return nil
        }

        return julianDate.addingDays(centuryOffset)
    }

    // swiftlint:enable identifier_name

    /// Calculates the day of Japanese Vernal Equinox for a given year
    /// Formula based on astronomical calculations for Japan
    static func calculateVernalEquinoxDay(year: Int) -> Int {
        // Simplified formula valid for 1900-2099
        let base = 20.8431
        let yearDiff = Double(year - 1_980)
        let day = Int(base + 0.242194 * yearDiff - floor(yearDiff / 4.0))
        return day
    }

    /// Calculates the day of Japanese Autumnal Equinox for a given year
    /// Formula based on astronomical calculations for Japan
    static func calculateAutumnalEquinoxDay(year: Int) -> Int {
        // Simplified formula valid for 1900-2099
        let base = 23.2488
        let yearDiff = Double(year - 1_980)
        let day = Int(base + 0.242194 * yearDiff - floor(yearDiff / 4.0))
        return day
    }

    /// Checks if date is Swedish Midsummer (Friday between June 19-25)
    static func isMidsummer(_ date: CalendarDate) -> Bool {
        guard date.month == 6 else { return false }
        guard date.day >= 19, date.day <= 25 else { return false }
        return date.weekday == 6 // Friday
    }

    /// Checks if date is Canadian Victoria Day (Monday on or before May 24)
    static func isVictoriaDay(_ date: CalendarDate) -> Bool {
        guard date.month == 5 else { return false }
        guard date.day >= 18, date.day <= 24 else { return false }
        guard date.weekday == 2 else { return false } // Must be Monday

        // Victoria Day is the last Monday on or before May 24
        // If adding 7 days would still be <= 24, there's a later Monday
        return date.day + 7 > 24
    }

    /// Checks if date is a Christmas/Boxing Day closure (including cascading substitutes)
    static func isChristmasBoxingDayClosure(_ date: CalendarDate) -> Bool {
        guard date.month == 12 else { return false }
        guard let closures = calculateChristmasBoxingDayClosures(for: date.year) else { return false }
        return closures.contains(date)
    }

    /// Calculates Christmas and Boxing Day closures with cascading substitutes
    /// Returns the actual closure dates (may be different from Dec 25/26 if they fall on weekends)
    static func calculateChristmasBoxingDayClosures(for year: Int) -> [CalendarDate]? {
        guard let christmas = CalendarDate(year: year, month: 12, day: 25),
              let boxingDay = CalendarDate(year: year, month: 12, day: 26) else {
            return nil
        }

        let christmasWeekday = christmas.weekday
        let boxingDayWeekday = boxingDay.weekday

        var closures: [CalendarDate] = []

        // Christmas: weekday 1=Sun, 2=Mon, ..., 6=Fri, 7=Sat
        switch christmasWeekday {
        case 7: // Saturday -> Monday (Dec 27)
            if let substitute = christmas.addingDays(2) {
                closures.append(substitute)
            }
        case 1: // Sunday -> Monday (Dec 26), but that's Boxing Day, so Tuesday (Dec 27)
            if let substitute = christmas.addingDays(2) {
                closures.append(substitute)
            }
        default: // Weekday - observed on actual date
            closures.append(christmas)
        }

        // Boxing Day
        switch boxingDayWeekday {
        case 7: // Saturday -> Monday (Dec 28)
            if let substitute = boxingDay.addingDays(2) {
                closures.append(substitute)
            }
        case 1: // Sunday -> Monday (Dec 27), but if Christmas is also on weekend, might cascade to Tuesday
            // When Dec 25 is Sat, Dec 26 is Sun: Dec 27 is Christmas substitute, Dec 28 is Boxing Day substitute
            if christmasWeekday == 7, let substitute = boxingDay.addingDays(2) {
                closures.append(substitute)
            } else if let substitute = boxingDay.addingDays(1) {
                closures.append(substitute)
            }
        default: // Weekday - observed on actual date
            closures.append(boxingDay)
        }

        return closures
    }
}

// MARK: - Codable

extension MarketClosureRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, month, day, name, nth, weekday, days, year
        case untilYear, fromYear
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "fixed":
            self = .fixed(
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                name: try container.decode(String.self, forKey: .name)
            )
        case "nthWeekday":
            self = .nthWeekday(
                month: try container.decode(Int.self, forKey: .month),
                nth: try container.decode(Int.self, forKey: .nth),
                weekday: try container.decode(Int.self, forKey: .weekday),
                name: try container.decode(String.self, forKey: .name)
            )
        case "lastWeekday":
            self = .lastWeekday(
                month: try container.decode(Int.self, forKey: .month),
                weekday: try container.decode(Int.self, forKey: .weekday),
                name: try container.decode(String.self, forKey: .name)
            )
        case "dayAfterNthWeekday":
            self = .dayAfterNthWeekday(
                month: try container.decode(Int.self, forKey: .month),
                nth: try container.decode(Int.self, forKey: .nth),
                weekday: try container.decode(Int.self, forKey: .weekday),
                name: try container.decode(String.self, forKey: .name)
            )
        case "easterOffset":
            self = .easterOffset(
                days: try container.decode(Int.self, forKey: .days),
                name: try container.decode(String.self, forKey: .name)
            )
        case "midsummer":
            self = .midsummer(
                name: try container.decode(String.self, forKey: .name)
            )
        case "victoriaDay":
            self = .victoriaDay(
                name: try container.decode(String.self, forKey: .name)
            )
        case "christmasBoxingDayCascade":
            self = .christmasBoxingDayCascade
        case "oneOff":
            self = .oneOff(
                year: try container.decode(Int.self, forKey: .year),
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                name: try container.decode(String.self, forKey: .name)
            )
        case "fixedWithBridge":
            self = .fixedWithBridge(
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                name: try container.decode(String.self, forKey: .name)
            )
        case "fixedWithObserved":
            self = .fixedWithObserved(
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                name: try container.decode(String.self, forKey: .name)
            )
        case "fixedWithSubstitute":
            self = .fixedWithSubstitute(
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                name: try container.decode(String.self, forKey: .name)
            )
        case "orthodoxEasterOffset":
            self = .orthodoxEasterOffset(
                days: try container.decode(Int.self, forKey: .days),
                name: try container.decode(String.self, forKey: .name)
            )
        case "easterOffsetUntilYear":
            self = .easterOffsetUntilYear(
                days: try container.decode(Int.self, forKey: .days),
                untilYear: try container.decode(Int.self, forKey: .untilYear),
                name: try container.decode(String.self, forKey: .name)
            )
        case "easterOffsetFromYear":
            self = .easterOffsetFromYear(
                days: try container.decode(Int.self, forKey: .days),
                fromYear: try container.decode(Int.self, forKey: .fromYear),
                name: try container.decode(String.self, forKey: .name)
            )
        case "fixedWithObservedFromYear":
            self = .fixedWithObservedFromYear(
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                fromYear: try container.decode(Int.self, forKey: .fromYear),
                name: try container.decode(String.self, forKey: .name)
            )
        case "japaneseVernalEquinox":
            self = .japaneseVernalEquinox(
                name: try container.decode(String.self, forKey: .name)
            )
        case "japaneseAutumnalEquinox":
            self = .japaneseAutumnalEquinox(
                name: try container.decode(String.self, forKey: .name)
            )
        case "fixedWithJapaneseSubstitute":
            self = .fixedWithJapaneseSubstitute(
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day),
                name: try container.decode(String.self, forKey: .name)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown MarketClosureRule type: \(type)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .fixed(month, day, name):
            try container.encode("fixed", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(name, forKey: .name)
        case let .nthWeekday(month, nth, weekday, name):
            try container.encode("nthWeekday", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(nth, forKey: .nth)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(name, forKey: .name)
        case let .lastWeekday(month, weekday, name):
            try container.encode("lastWeekday", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(name, forKey: .name)
        case let .dayAfterNthWeekday(month, nth, weekday, name):
            try container.encode("dayAfterNthWeekday", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(nth, forKey: .nth)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(name, forKey: .name)
        case let .easterOffset(days, name):
            try container.encode("easterOffset", forKey: .type)
            try container.encode(days, forKey: .days)
            try container.encode(name, forKey: .name)
        case let .midsummer(name):
            try container.encode("midsummer", forKey: .type)
            try container.encode(name, forKey: .name)
        case let .victoriaDay(name):
            try container.encode("victoriaDay", forKey: .type)
            try container.encode(name, forKey: .name)
        case .christmasBoxingDayCascade:
            try container.encode("christmasBoxingDayCascade", forKey: .type)
        case let .oneOff(year, month, day, name):
            try container.encode("oneOff", forKey: .type)
            try container.encode(year, forKey: .year)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(name, forKey: .name)
        case let .fixedWithBridge(month, day, name):
            try container.encode("fixedWithBridge", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(name, forKey: .name)
        case let .fixedWithObserved(month, day, name):
            try container.encode("fixedWithObserved", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(name, forKey: .name)
        case let .fixedWithSubstitute(month, day, name):
            try container.encode("fixedWithSubstitute", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(name, forKey: .name)
        case let .orthodoxEasterOffset(days, name):
            try container.encode("orthodoxEasterOffset", forKey: .type)
            try container.encode(days, forKey: .days)
            try container.encode(name, forKey: .name)
        case let .easterOffsetUntilYear(days, untilYear, name):
            try container.encode("easterOffsetUntilYear", forKey: .type)
            try container.encode(days, forKey: .days)
            try container.encode(untilYear, forKey: .untilYear)
            try container.encode(name, forKey: .name)
        case let .easterOffsetFromYear(days, fromYear, name):
            try container.encode("easterOffsetFromYear", forKey: .type)
            try container.encode(days, forKey: .days)
            try container.encode(fromYear, forKey: .fromYear)
            try container.encode(name, forKey: .name)
        case let .fixedWithObservedFromYear(month, day, fromYear, name):
            try container.encode("fixedWithObservedFromYear", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(fromYear, forKey: .fromYear)
            try container.encode(name, forKey: .name)
        case let .japaneseVernalEquinox(name):
            try container.encode("japaneseVernalEquinox", forKey: .type)
            try container.encode(name, forKey: .name)
        case let .japaneseAutumnalEquinox(name):
            try container.encode("japaneseAutumnalEquinox", forKey: .type)
            try container.encode(name, forKey: .name)
        case let .fixedWithJapaneseSubstitute(month, day, name):
            try container.encode("fixedWithJapaneseSubstitute", forKey: .type)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(name, forKey: .name)
        }
    }
}
