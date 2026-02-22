import Foundation
import TradingCalendar
import Testing

@Suite("TradingCalendar Unit Tests")
struct TradingCalendarUnitTests {
    @Test("Swedish holidays are correctly identified via MIC")
    func swedishHolidaysViaMIC() {
        let mic = MIC.XSTO

        let holidays: [(CalendarDate, String)] = [
            (CalendarDate(year: 2_023, month: 12, day: 25)!, "Christmas"),
            (CalendarDate(year: 2_023, month: 6, day: 6)!, "National Day"),
            (CalendarDate(year: 2_023, month: 1, day: 6)!, "Epiphany"),
            (CalendarDate(year: 2_023, month: 5, day: 1)!, "May Day"),
        ]

        for (date, name) in holidays {
            let isBusinessDay = TradingCalendar.isBusinessDay(date, mic: mic)
            #expect(!isBusinessDay, "\(name) (\(date)) should not be a business day")
        }
    }

    @Test("Finnish Independence Day is correctly identified")
    func finnishIndependenceDay() {
        let mic = MIC.XHEL

        // Dec 6 is Independence Day in Finland
        let independenceDay2023 = CalendarDate(year: 2_023, month: 12, day: 6)!
        let independenceDay2024 = CalendarDate(year: 2_024, month: 12, day: 6)!

        #expect(!TradingCalendar.isBusinessDay(independenceDay2023, mic: mic), "2023 Independence Day should be closed")
        #expect(!TradingCalendar.isBusinessDay(independenceDay2024, mic: mic), "2024 Independence Day should be closed")
    }

    @Test("Danish Great Prayer Day was abolished in 2024")
    func danishGreatPrayerDay() {
        let mic = MIC.XCSE

        // Great Prayer Day 2023 (May 5) - should be closed
        let greatPrayerDay2023 = CalendarDate(year: 2_023, month: 5, day: 5)!
        #expect(!TradingCalendar.isBusinessDay(greatPrayerDay2023, mic: mic), "2023 Great Prayer Day should be closed")

        // Great Prayer Day 2024 would have been May 3, but it was abolished
        // May 3, 2024 is a Friday - should be open
        let may3_2024 = CalendarDate(year: 2_024, month: 5, day: 3)!
        #expect(TradingCalendar.isBusinessDay(may3_2024, mic: mic), "2024 May 3 should be open (Great Prayer Day abolished)")
    }

    @Test("Regular weekdays are business days")
    func regularWeekdays() {
        // A regular Wednesday that's not a holiday
        let regularDay = CalendarDate(year: 2_024, month: 3, day: 13)! // March 13, 2024 is a Wednesday

        #expect(TradingCalendar.isBusinessDay(regularDay, mic: .XSTO), "Regular Wednesday should be a business day")
        #expect(TradingCalendar.isBusinessDay(regularDay, mic: .XOSL), "Regular Wednesday should be a business day")
        #expect(TradingCalendar.isBusinessDay(regularDay, mic: .XCSE), "Regular Wednesday should be a business day")
        #expect(TradingCalendar.isBusinessDay(regularDay, mic: .XHEL), "Regular Wednesday should be a business day")
    }

    @Test("Weekends are not business days")
    func weekends() {
        let saturday = CalendarDate(year: 2_024, month: 3, day: 16)!
        let sunday = CalendarDate(year: 2_024, month: 3, day: 17)!

        #expect(!TradingCalendar.isBusinessDay(saturday, mic: .XSTO), "Saturday should not be a business day")
        #expect(!TradingCalendar.isBusinessDay(sunday, mic: .XSTO), "Sunday should not be a business day")
    }

    @Test("businessDayCount returns correct count")
    func businessDayCount() {
        // A week Mon-Fri with no holidays
        let monday = CalendarDate(year: 2_024, month: 3, day: 11)!
        let friday = CalendarDate(year: 2_024, month: 3, day: 15)!

        #expect(TradingCalendar.businessDayCount(from: monday, to: friday) == 5)
    }

    @Test("nextBusinessDay skips weekends and holidays")
    func nextBusinessDay() {
        // Friday before a regular weekend
        let friday = CalendarDate(year: 2_024, month: 3, day: 15)!
        let nextBD = TradingCalendar.nextBusinessDay(from: friday)
        let expectedMonday = CalendarDate(year: 2_024, month: 3, day: 18)!
        #expect(nextBD == expectedMonday)
    }

    @Test("addBusinessDays correctly skips non-business days")
    func addBusinessDays() {
        // Start on Monday, add 5 business days = next Monday
        let monday = CalendarDate(year: 2_024, month: 3, day: 11)!
        let result = TradingCalendar.addBusinessDays(5, from: monday)
        let expectedMonday = CalendarDate(year: 2_024, month: 3, day: 18)!
        #expect(result == expectedMonday)
    }

    @Test("country(for:) returns correct country")
    func countryForMIC() {
        #expect(TradingCalendar.country(for: .XNYS) == .us)
        #expect(TradingCalendar.country(for: .XLON) == .gb)
        #expect(TradingCalendar.country(for: .XSTO) == .se)
        #expect(TradingCalendar.country(for: .XTKS) == .jp)
    }

    @Test("XEUE has no country mapping")
    func xeueNoCountryMapping() {
        #expect(TradingCalendar.country(for: .XEUE) == nil)
    }

    @Test("XEUE exchange-wide holidays are correctly identified")
    func xeueExchangeHolidays() {
        // Eurex exchange-wide holidays for 2024
        let newYears = CalendarDate(year: 2_024, month: 1, day: 1)!
        let goodFriday = CalendarDate(year: 2_024, month: 3, day: 29)! // 2024 Good Friday
        let easterMonday = CalendarDate(year: 2_024, month: 4, day: 1)! // 2024 Easter Monday
        let labourDay = CalendarDate(year: 2_024, month: 5, day: 1)!
        let christmasEve = CalendarDate(year: 2_024, month: 12, day: 24)!
        let christmasDay = CalendarDate(year: 2_024, month: 12, day: 25)!
        let newYearsEve = CalendarDate(year: 2_024, month: 12, day: 31)!

        #expect(!TradingCalendar.isBusinessDay(newYears, mic: .XEUE))
        #expect(!TradingCalendar.isBusinessDay(goodFriday, mic: .XEUE))
        #expect(!TradingCalendar.isBusinessDay(easterMonday, mic: .XEUE))
        #expect(!TradingCalendar.isBusinessDay(labourDay, mic: .XEUE))
        #expect(!TradingCalendar.isBusinessDay(christmasEve, mic: .XEUE))
        #expect(!TradingCalendar.isBusinessDay(christmasDay, mic: .XEUE))
        #expect(!TradingCalendar.isBusinessDay(newYearsEve, mic: .XEUE))

        #expect(TradingCalendar.nonBusinessDayReason(newYears, mic: .XEUE) == .holiday(name: "New Year's Day"))
        #expect(TradingCalendar.nonBusinessDayReason(labourDay, mic: .XEUE) == .holiday(name: "Labour Day"))
    }

    @Test("XEUE does not observe Boxing Day (not an exchange-wide holiday)")
    func xeueNoBoxingDay() {
        // Dec 26, 2024 is a Thursday — not an Eurex exchange-wide holiday
        let boxingDay = CalendarDate(year: 2_024, month: 12, day: 26)!
        #expect(TradingCalendar.isBusinessDay(boxingDay, mic: .XEUE))
        #expect(TradingCalendar.nonBusinessDayReason(boxingDay, mic: .XEUE) == .businessDay)
    }

    @Test("XEUE with German underlying observes Boxing Day")
    func xeueWithGermanUnderlying() {
        // Dec 26, 2024 is a Thursday — Boxing Day in Germany but not Eurex exchange-wide
        let boxingDay = CalendarDate(year: 2_024, month: 12, day: 26)!
        #expect(!TradingCalendar.isBusinessDay(boxingDay, mic: .XEUE, underlyingMIC: .XETR))
        #expect(TradingCalendar.nonBusinessDayReason(boxingDay, mic: .XEUE, underlyingMIC: .XETR) == .holiday(name: "Boxing Day"))
    }

    @Test("XEUE with UK underlying observes UK holidays")
    func xeueWithUKUnderlying() {
        // Aug 26, 2024 is Summer Bank Holiday in UK (last Monday in Aug)
        let summerBankHoliday = CalendarDate(year: 2_024, month: 8, day: 26)!
        #expect(TradingCalendar.isBusinessDay(summerBankHoliday, mic: .XEUE), "XEUE alone is open")
        #expect(!TradingCalendar.isBusinessDay(summerBankHoliday, mic: .XEUE, underlyingMIC: .XLON), "Closed due to UK underlying")
    }

    @Test("XEUE with US underlying ignores XEUE Labour Day")
    func xeueWithUSUnderlying() {
        // May 1, 2025 is Labour Day — XEUE is closed, but XNYS is open.
        // The underlying moves, so this IS a volatility day.
        let labourDay = CalendarDate(year: 2_025, month: 5, day: 1)!
        #expect(!TradingCalendar.isBusinessDay(labourDay, mic: .XEUE), "XEUE alone is closed on Labour Day")
        #expect(TradingCalendar.isBusinessDay(labourDay, mic: .XNYS), "XNYS is open on May 1")
        #expect(TradingCalendar.isBusinessDay(labourDay, mic: .XEUE, underlyingMIC: .XNYS), "Underlying is open — volatility day")
        #expect(TradingCalendar.nonBusinessDayReason(labourDay, mic: .XEUE, underlyingMIC: .XNYS) == .businessDay)
    }

    @Test("Cross-market: Swedish derivative with Finnish underlying")
    func swedishDerivativeFinnishUnderlying() {
        // Finnish Independence Day: Dec 6, 2024 (Friday) — closed in Finland, open in Sweden
        // With underlyingMIC, the underlying's calendar is used exclusively:
        // the underlying doesn't move, so this is NOT a volatility day.
        let finnishIndependenceDay = CalendarDate(year: 2_024, month: 12, day: 6)!
        #expect(TradingCalendar.isBusinessDay(finnishIndependenceDay, mic: .XSTO), "Sweden is open on Dec 6")
        #expect(!TradingCalendar.isBusinessDay(finnishIndependenceDay, mic: .XHEL), "Finland is closed on Dec 6")
        #expect(!TradingCalendar.isBusinessDay(finnishIndependenceDay, mic: .XSTO, underlyingMIC: .XHEL), "Underlying is closed")
        #expect(TradingCalendar.nonBusinessDayReason(finnishIndependenceDay, mic: .XSTO, underlyingMIC: .XHEL) == .holiday(name: "Independence Day"))

        // Swedish National Day 2024: June 6 (Thursday) — closed in Sweden, open in Finland
        // The derivative exchange (XSTO) is closed, but the underlying (XHEL) is open —
        // the underlying IS moving, so this IS a volatility day.
        let nationalDay = CalendarDate(year: 2_024, month: 6, day: 6)!
        #expect(!TradingCalendar.isBusinessDay(nationalDay, mic: .XSTO), "Sweden is closed on National Day")
        #expect(TradingCalendar.isBusinessDay(nationalDay, mic: .XHEL), "Finland is open on Swedish National Day")
        #expect(TradingCalendar.isBusinessDay(nationalDay, mic: .XSTO, underlyingMIC: .XHEL), "Underlying is open — volatility day")
        #expect(TradingCalendar.nonBusinessDayReason(nationalDay, mic: .XSTO, underlyingMIC: .XHEL) == .businessDay)
    }

    @Test("underlyingMIC with same country is a no-op")
    func underlyingMICSameCountry() {
        // Two Swedish MICs — should behave the same as just one
        let regularDay = CalendarDate(year: 2_024, month: 3, day: 13)!
        #expect(TradingCalendar.isBusinessDay(regularDay, mic: .XSTO, underlyingMIC: .XNGM))

        let midsummer2024 = CalendarDate(year: 2_024, month: 6, day: 21)!
        #expect(!TradingCalendar.isBusinessDay(midsummer2024, mic: .XSTO, underlyingMIC: .XNGM))
    }

    // MARK: - New tests for Phase 2/3 features

    @Test("CalendarDate Codable round-trip")
    func calendarDateCodable() throws {
        let date = CalendarDate(year: 2_024, month: 6, day: 15)!
        let data = try JSONEncoder().encode(date)
        let decoded = try JSONDecoder().decode(CalendarDate.self, from: data)
        #expect(decoded == date)
    }

    @Test("MarketClosureRule Codable round-trip")
    func marketClosureRuleCodable() throws {
        let rules: [MarketClosureRule] = [
            .fixed(month: 1, day: 1, name: "New Year's Day"),
            .nthWeekday(month: 1, nth: 3, weekday: 2, name: "MLK Day"),
            .easterOffset(days: -2, name: "Good Friday"),
            .midsummer(name: "Midsummer"),
            .christmasBoxingDayCascade,
            .oneOff(year: 2022, month: 9, day: 19, name: "State Funeral"),
        ]

        for rule in rules {
            let data = try JSONEncoder().encode(rule)
            let decoded = try JSONDecoder().decode(MarketClosureRule.self, from: data)
            #expect(decoded.name == rule.name, "Round-trip failed for \(rule.name)")
        }
    }

    @Test("ExchangeCalendar Codable round-trip")
    func exchangeCalendarCodable() throws {
        let calendar = ExchangeCalendar(
            name: "Test Exchange",
            closureRules: [
                .fixed(month: 1, day: 1, name: "New Year's Day"),
                .easterOffset(days: -2, name: "Good Friday"),
            ],
            session: TradingSession(
                open: TimeOfDay(hour: 9, minute: 0),
                close: TimeOfDay(hour: 17, minute: 30)
            ),
            shortenedSessions: [
                ShortenedSession(
                    rule: .fixed(month: 12, day: 24, name: "Christmas Eve"),
                    session: TradingSession(
                        open: TimeOfDay(hour: 9, minute: 0),
                        close: TimeOfDay(hour: 13, minute: 0)
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(calendar)
        let decoded = try JSONDecoder().decode(ExchangeCalendar.self, from: data)
        #expect(decoded.name == "Test Exchange")
        #expect(decoded.closureRules.count == 2)
        #expect(decoded.session?.open.hour == 9)
        #expect(decoded.shortenedSessions.count == 1)
    }

    @Test("Custom exchange calendar registration")
    func customCalendarRegistration() throws {
        let customMIC = MIC("XTES")
        let calendar = ExchangeCalendar(
            name: "Test Exchange",
            closureRules: [
                .fixed(month: 1, day: 1, name: "New Year's Day"),
                .fixed(month: 12, day: 25, name: "Christmas Day"),
            ]
        )

        TradingCalendar.register(calendar, for: customMIC)

        // Jan 1, 2024 is a Monday — should be closed
        let newYears = CalendarDate(year: 2_024, month: 1, day: 1)!
        #expect(!TradingCalendar.isBusinessDay(newYears, mic: customMIC))

        // Jan 2, 2024 is a Tuesday — should be open
        let jan2 = CalendarDate(year: 2_024, month: 1, day: 2)!
        #expect(TradingCalendar.isBusinessDay(jan2, mic: customMIC))

        // Verify the calendar is retrievable
        let retrieved = TradingCalendar.exchangeCalendar(for: customMIC)
        #expect(retrieved?.name == "Test Exchange")
    }

    @Test("Trading session returns correct session for built-in exchanges")
    func tradingSessionBuiltIn() {
        let regularDay = CalendarDate(year: 2_024, month: 3, day: 13)! // Wednesday

        // Stockholm normal session
        let xstoSession = TradingCalendar.tradingSession(on: regularDay, mic: .XSTO)
        #expect(xstoSession?.open == TimeOfDay(hour: 9, minute: 0))
        #expect(xstoSession?.close == TimeOfDay(hour: 17, minute: 30))

        // NYSE normal session
        let xnysSession = TradingCalendar.tradingSession(on: regularDay, mic: .XNYS)
        #expect(xnysSession?.open == TimeOfDay(hour: 9, minute: 30))
        #expect(xnysSession?.close == TimeOfDay(hour: 16, minute: 0))

        // Weekend returns nil
        let saturday = CalendarDate(year: 2_024, month: 3, day: 16)!
        #expect(TradingCalendar.tradingSession(on: saturday, mic: .XSTO) == nil)
    }

    @Test("MIC is ExpressibleByStringLiteral and Codable")
    func micStringLiteralAndCodable() throws {
        let mic: MIC = "XSTO"
        #expect(mic.code == "XSTO")
        #expect(mic == MIC.XSTO)

        let data = try JSONEncoder().encode(mic)
        let decoded = try JSONDecoder().decode(MIC.self, from: data)
        #expect(decoded == mic)
    }

    @Test("Country is Codable via rawValue")
    func countryCodable() throws {
        let country = Country.se
        let data = try JSONEncoder().encode(country)
        let decoded = try JSONDecoder().decode(Country.self, from: data)
        #expect(decoded == .se)
        #expect(decoded.name == "Sweden")
    }
}
