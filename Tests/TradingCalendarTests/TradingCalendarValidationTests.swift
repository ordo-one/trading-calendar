import Foundation
import TradingCalendar
import Testing

// MARK: - Fixture Types

struct MarketFixture: Codable {
    let market: String
    let symbol: String
    let country: String
    let fetchedAt: String
    let dateRange: DateRange
    let tradingDatesCount: Int
    let tradingDates: [String]

    struct DateRange: Codable {
        let start: String
        let end: String
    }
}

// MARK: - Discrepancy Types

enum DiscrepancyType: CustomStringConvertible {
    /// Yahoo had data for this date, but TradingCalendar says it's not a business day
    case yahooTradedButCalendarSaysClosed

    /// TradingCalendar says this is a business day, but Yahoo had no data
    case calendarSaysOpenButNoYahooData

    var description: String {
        switch self {
        case .yahooTradedButCalendarSaysClosed:
            "YAHOO_TRADED_BUT_CALENDAR_SAYS_CLOSED"
        case .calendarSaysOpenButNoYahooData:
            "CALENDAR_SAYS_OPEN_BUT_NO_YAHOO_DATA"
        }
    }
}

struct Discrepancy: CustomStringConvertible {
    let market: String
    let date: CalendarDate
    let type: DiscrepancyType

    var description: String {
        "\(market) \(date.year)-\(String(format: "%02d", date.month))-\(String(format: "%02d", date.day)): \(type)"
    }
}

// MARK: - Expected Discrepancies

struct ExpectedDiscrepancy {
    let market: String
    let date: CalendarDate
    let type: DiscrepancyType
    let reason: String
}

let expectedDiscrepancies: [ExpectedDiscrepancy] = [
    ExpectedDiscrepancy(
        market: "XLON",
        date: CalendarDate(year: 2_020, month: 5, day: 4)!,
        type: .yahooTradedButCalendarSaysClosed,
        reason: "Early May BH moved to May 8 for VE Day 75th anniversary"
    ),
    ExpectedDiscrepancy(
        market: "XLON",
        date: CalendarDate(year: 2_022, month: 5, day: 30)!,
        type: .yahooTradedButCalendarSaysClosed,
        reason: "Spring Bank Holiday moved to June 2-3 for Queen's Platinum Jubilee"
    ),
    ExpectedDiscrepancy(
        market: "CHIX",
        date: CalendarDate(year: 2_022, month: 5, day: 30)!,
        type: .yahooTradedButCalendarSaysClosed,
        reason: "Spring Bank Holiday moved to June 2-3 for Queen's Platinum Jubilee"
    ),
    ExpectedDiscrepancy(
        market: "ASEX",
        date: CalendarDate(year: 2_021, month: 5, day: 4)!,
        type: .calendarSaysOpenButNoYahooData,
        reason: "Yahoo data gap or stock-specific halt (BELA.AT)"
    ),
    ExpectedDiscrepancy(
        market: "ASEX",
        date: CalendarDate(year: 2_024, month: 5, day: 7)!,
        type: .calendarSaysOpenButNoYahooData,
        reason: "Yahoo data gap or stock-specific halt (BELA.AT)"
    ),
    ExpectedDiscrepancy(
        market: "XTKS",
        date: CalendarDate(year: 2_021, month: 7, day: 19)!,
        type: .yahooTradedButCalendarSaysClosed,
        reason: "2021 Olympics: Marine Day moved to July 22"
    ),
    ExpectedDiscrepancy(
        market: "XTKS",
        date: CalendarDate(year: 2_021, month: 10, day: 11)!,
        type: .yahooTradedButCalendarSaysClosed,
        reason: "2021 Olympics: Sports Day moved to July 23"
    ),
    ExpectedDiscrepancy(
        market: "XTKS",
        date: CalendarDate(year: 2_021, month: 8, day: 11)!,
        type: .yahooTradedButCalendarSaysClosed,
        reason: "2021 Olympics: Mountain Day moved to August 9"
    ),
]

// MARK: - Test Suite

@Suite("TradingCalendar Validation Tests")
struct TradingCalendarValidationTests {
    // MARK: - Helpers

    private func micFromString(_ micStr: String) -> MIC? {
        switch micStr {
        case "XSTO": return .XSTO
        case "XOSL": return .XOSL
        case "XCSE": return .XCSE
        case "XHEL": return .XHEL
        case "XLON", "XLON_2012": return .XLON
        case "XETR": return .XETR
        case "XPAR": return .XPAR
        case "XAMS": return .XAMS
        case "XMAD": return .XMAD
        case "MTAA": return .MTAA
        case "XNYS": return .XNYS
        case "XNAS": return .XNAS
        case "XSWX": return .XSWX
        case "XWBO": return .XWBO
        case "XWAR": return .XWAR
        case "XBUD": return .XBUD
        case "XPRA": return .XPRA
        case "XBRU": return .XBRU
        case "XDUB": return .XDUB
        case "XLIS": return .XLIS
        case "ASEX": return .ASEX
        case "XTKS": return .XTKS
        case "XASX": return .XASX
        case "XTSE": return .XTSE
        case "CHIX": return .CHIX
        default: return nil
        }
    }

    private func loadFixture(for market: String) throws -> MarketFixture {
        let fixturesPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(market).json")

        let data = try Data(contentsOf: fixturesPath)
        return try JSONDecoder().decode(MarketFixture.self, from: data)
    }

    private func parseDate(_ dateString: String) -> CalendarDate? {
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return CalendarDate(year: parts[0], month: parts[1], day: parts[2])
    }

    private func findDiscrepancies(fixture: MarketFixture) -> [Discrepancy] {
        var discrepancies: [Discrepancy] = []

        let yahooTradingDates = Set(fixture.tradingDates.compactMap { parseDate($0) })

        guard let startDate = parseDate(fixture.dateRange.start),
              let endDate = parseDate(fixture.dateRange.end) else {
            return discrepancies
        }

        guard let mic = micFromString(fixture.market) else {
            print("WARNING: Unknown market \(fixture.market), cannot validate")
            return discrepancies
        }

        var currentDate = startDate
        while currentDate <= endDate {
            let isYahooTradingDay = yahooTradingDates.contains(currentDate)
            let isCalendarBusinessDay = TradingCalendar.isBusinessDay(currentDate, mic: mic)

            if isYahooTradingDay && !isCalendarBusinessDay {
                discrepancies.append(Discrepancy(
                    market: fixture.market,
                    date: currentDate,
                    type: .yahooTradedButCalendarSaysClosed
                ))
            } else if !isYahooTradingDay && isCalendarBusinessDay {
                if !isWeekend(currentDate) {
                    discrepancies.append(Discrepancy(
                        market: fixture.market,
                        date: currentDate,
                        type: .calendarSaysOpenButNoYahooData
                    ))
                }
            }

            guard let nextDate = currentDate.nextDay else { break }
            currentDate = nextDate
        }

        return discrepancies
    }

    private func isWeekend(_ date: CalendarDate) -> Bool {
        let weekday = date.weekday
        return weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
    }

    private func filterExpectedDiscrepancies(_ discrepancies: [Discrepancy]) -> (unexpected: [Discrepancy], expected: [Discrepancy]) {
        var unexpected: [Discrepancy] = []
        var expected: [Discrepancy] = []

        for discrepancy in discrepancies {
            let isExpected = expectedDiscrepancies.contains { exp in
                exp.market == discrepancy.market &&
                    exp.date == discrepancy.date &&
                    exp.type == discrepancy.type
            }
            if isExpected {
                expected.append(discrepancy)
            } else {
                unexpected.append(discrepancy)
            }
        }

        return (unexpected, expected)
    }

    // MARK: - Validation Test

    private func validateMarket(_ market: String) throws {
        let fixture = try loadFixture(for: market)
        let discrepancies = findDiscrepancies(fixture: fixture)
        let (unexpected, expected) = filterExpectedDiscrepancies(discrepancies)

        print("\n=== \(market) (\(fixture.symbol)) ===")
        print("Date range: \(fixture.dateRange.start) to \(fixture.dateRange.end)")
        print("Yahoo trading days: \(fixture.tradingDatesCount)")
        print("Total discrepancies: \(discrepancies.count)")
        print("Expected (verified): \(expected.count)")
        print("Unexpected (need review): \(unexpected.count)")

        if !unexpected.isEmpty {
            print("\n--- UNEXPECTED DISCREPANCIES (need manual review) ---")

            let yahooTraded = unexpected.filter { $0.type == .yahooTradedButCalendarSaysClosed }
            let calendarOnly = unexpected.filter { $0.type == .calendarSaysOpenButNoYahooData }

            if !yahooTraded.isEmpty {
                print("\nYahoo traded but calendar says closed (\(yahooTraded.count)):")
                for d in yahooTraded.prefix(20) {
                    print("  - \(d)")
                }
                if yahooTraded.count > 20 {
                    print("  ... and \(yahooTraded.count - 20) more")
                }
            }

            if !calendarOnly.isEmpty {
                print("\nCalendar says open but no Yahoo data (\(calendarOnly.count)):")
                for d in calendarOnly.prefix(20) {
                    print("  - \(d)")
                }
                if calendarOnly.count > 20 {
                    print("  ... and \(calendarOnly.count - 20) more")
                }
            }
        }
    }

    // MARK: - Tests

    @Test("Validate XSTO (Stockholm) against Yahoo data")
    func validateXSTO() throws { try validateMarket("XSTO") }

    @Test("Validate XOSL (Oslo) against Yahoo data")
    func validateXOSL() throws { try validateMarket("XOSL") }

    @Test("Validate XCSE (Copenhagen) against Yahoo data")
    func validateXCSE() throws { try validateMarket("XCSE") }

    @Test("Validate XHEL (Helsinki) against Yahoo data")
    func validateXHEL() throws { try validateMarket("XHEL") }

    @Test("Validate XLON (London) against Yahoo data")
    func validateXLON() throws { try validateMarket("XLON") }

    @Test("Validate XLON_2012 (London 2012) against Yahoo data")
    func validateXLON2012() throws { try validateMarket("XLON_2012") }

    @Test("Validate XETR (Frankfurt) against Yahoo data")
    func validateXETR() throws { try validateMarket("XETR") }

    @Test("Validate XPAR (Paris) against Yahoo data")
    func validateXPAR() throws { try validateMarket("XPAR") }

    @Test("Validate XAMS (Amsterdam) against Yahoo data")
    func validateXAMS() throws { try validateMarket("XAMS") }

    @Test("Validate XMAD (Madrid) against Yahoo data")
    func validateXMAD() throws { try validateMarket("XMAD") }

    @Test("Validate MTAA (Milan) against Yahoo data")
    func validateMTAA() throws { try validateMarket("MTAA") }

    @Test("Validate XSWX (Zurich) against Yahoo data")
    func validateXSWX() throws { try validateMarket("XSWX") }

    @Test("Validate XNYS (NYSE) against Yahoo data")
    func validateXNYS() throws { try validateMarket("XNYS") }

    @Test("Validate XNAS (NASDAQ) against Yahoo data")
    func validateXNAS() throws { try validateMarket("XNAS") }

    @Test("Validate XWBO (Vienna) against Yahoo data")
    func validateXWBO() throws { try validateMarket("XWBO") }

    @Test("Validate XWAR (Warsaw) against Yahoo data")
    func validateXWAR() throws { try validateMarket("XWAR") }

    @Test("Validate XBUD (Budapest) against Yahoo data")
    func validateXBUD() throws { try validateMarket("XBUD") }

    @Test("Validate XPRA (Prague) against Yahoo data")
    func validateXPRA() throws { try validateMarket("XPRA") }

    @Test("Validate XBRU (Brussels) against Yahoo data")
    func validateXBRU() throws { try validateMarket("XBRU") }

    @Test("Validate XDUB (Dublin) against Yahoo data")
    func validateXDUB() throws { try validateMarket("XDUB") }

    @Test("Validate XLIS (Lisbon) against Yahoo data")
    func validateXLIS() throws { try validateMarket("XLIS") }

    @Test("Validate ASEX (Athens) against Yahoo data")
    func validateASEX() throws { try validateMarket("ASEX") }

    @Test("Validate XTKS (Tokyo) against Yahoo data")
    func validateXTKS() throws { try validateMarket("XTKS") }

    @Test("Validate XASX (Sydney) against Yahoo data")
    func validateXASX() throws { try validateMarket("XASX") }

    @Test("Validate XTSE (Toronto) against Yahoo data")
    func validateXTSE() throws { try validateMarket("XTSE") }

    @Test("Validate CHIX (CBOE Europe CXE) against Yahoo data")
    func validateCHIX() throws { try validateMarket("CHIX") }
}
