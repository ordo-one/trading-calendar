import Foundation
import Synchronization

/// Represents why a day is not a business day
public enum NonBusinessDayReason: Equatable, Sendable {
    case weekend
    case holiday(name: String)
    case businessDay // It IS a business day
}

/// Utility for working with business days and market trading closures
public enum TradingCalendar {
    // MARK: - Market Closure Cache

    private struct CacheKey: Hashable, Sendable {
        let year: Int
        let country: Country
    }

    private struct ExchangeCacheKey: Hashable, Sendable {
        let year: Int
        let mic: String
    }

    private struct CacheState: Sendable {
        var closures: [CacheKey: Set<CalendarDate>] = [:]
        var exchangeClosures: [ExchangeCacheKey: Set<CalendarDate>] = [:]
        var isPrewarmed = false
    }

    private static let cache = Mutex<CacheState>(.init())

    // MARK: - Exchange Calendar Registry

    private struct RegistryState: Sendable {
        var calendars: [String: ExchangeCalendar] = [:]
    }

    private static let registry = Mutex<RegistryState>(.init())

    /// Registers a custom exchange calendar for a MIC code.
    /// Overrides any built-in calendar for the same MIC.
    public static func register(_ calendar: ExchangeCalendar, for mic: MIC) {
        registry.withLock { $0.calendars[mic.code] = calendar }
        // Invalidate cached closures for this MIC
        cache.withLock { state in
            state.exchangeClosures = state.exchangeClosures.filter { $0.key.mic != mic.code }
        }
    }

    /// Returns the exchange calendar registered for a MIC code, if any.
    public static func exchangeCalendar(for mic: MIC) -> ExchangeCalendar? {
        registry.withLock { $0.calendars[mic.code] }
    }

    /// Registers an exchange calendar from JSON data for a MIC code.
    public static func register(from jsonData: Data, for mic: MIC) throws {
        let calendar = try JSONDecoder().decode(ExchangeCalendar.self, from: jsonData)
        register(calendar, for: mic)
    }

    /// Returns the trading session for a given date and MIC.
    /// Returns nil if the market is closed on that date.
    /// Returns a shortened session if a half-day rule matches.
    /// Returns the normal session otherwise.
    public static func tradingSession(on date: CalendarDate, mic: MIC) -> TradingSession? {
        guard isBusinessDay(date, mic: mic) else { return nil }

        // Check registered calendar first
        if let calendar = exchangeCalendar(for: mic) {
            let easter = MarketClosureRule.calculateEaster(year: date.year)
            for shortened in calendar.shortenedSessions {
                if shortened.rule.matches(date, preCalculatedEaster: easter) {
                    return shortened.session
                }
            }
            return calendar.session
        }

        // Check built-in exchange sessions
        if let session = builtInTradingSession(on: date, mic: mic) {
            return session
        }

        return nil
    }

    /// Pre-warm the cache with common years and countries
    public static func prewarmCache() {
        cache.withLock { state in
            guard !state.isPrewarmed else { return }

            let currentYear = CalendarDate.today.year
            let years = [currentYear - 1, currentYear, currentYear + 1]
            let commonCountries: [Country] = [.us, .gb, .se, .no, .dk, .fi, .de, .fr, .nl, .be, .es, .it, .ch]

            for year in years {
                for country in commonCountries {
                    let key = CacheKey(year: year, country: country)
                    if state.closures[key] == nil {
                        state.closures[key] = marketClosuresForYearUnsafe(year, country: country)
                    }
                }
            }

            state.isPrewarmed = true
        }
    }

    // MARK: - Public API (MIC-based)

    /// Checks if a CalendarDate falls on a business day (Monday-Friday, excluding market closures)
    /// - Parameters:
    ///   - date: The date to check
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    public static func isBusinessDay(_ date: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> Bool {
        guard date.isWeekday else { return false }

        // When underlyingMIC is provided, use the underlying's calendar exclusively.
        // This answers "does the underlying move today?" — the relevant question
        // for option pricing and volatility day counting.
        if let underlyingMIC, !sharesClosureRules(mic, underlyingMIC) {
            return !isMarketClosed(date, mic: underlyingMIC)
        }

        if let mic, isMarketClosed(date, mic: mic) {
            return false
        }

        return true
    }

    /// Returns the reason a day is not a business day, or `.businessDay` if it is one
    /// - Parameters:
    ///   - date: The date to check
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market.
    ///     When provided, the underlying's calendar is used exclusively (the derivative
    ///     exchange's own holidays are ignored).
    public static func nonBusinessDayReason(_ date: CalendarDate, mic: MIC?, underlyingMIC: MIC? = nil) -> NonBusinessDayReason {
        guard date.isWeekday else { return .weekend }

        // When underlyingMIC is provided, use the underlying's calendar exclusively.
        if let underlyingMIC, !sharesClosureRules(mic, underlyingMIC) {
            if let name = findHolidayName(date, mic: underlyingMIC) {
                return .holiday(name: name)
            }
            return .businessDay
        }

        if let mic, let name = findHolidayName(date, mic: mic) {
            return .holiday(name: name)
        }

        return .businessDay
    }

    /// Returns all business days (weekdays excluding market closures) in the given date range, inclusive
    /// - Parameters:
    ///   - start: Start date
    ///   - end: End date
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    public static func allBusinessDays(from start: CalendarDate, to end: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> [CalendarDate] {
        var dates: [CalendarDate] = []
        var current = start

        while current <= end {
            if isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
                dates.append(current)
            }

            guard let next = current.nextDay else { break }
            current = next
        }

        return dates
    }

    /// Finds the most recent business day on or before the given date
    /// If the given date is a business day, returns it
    /// Otherwise, walks backward to find the previous business day
    /// - Parameters:
    ///   - date: The date to start from
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    public static func previousBusinessDay(from date: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> CalendarDate? {
        var current = date

        // If current date is already a business day, return it
        if isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
            return current
        }

        // Walk backward to find the most recent business day
        while let previous = current.previousDay {
            current = previous
            if isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
                return current
            }
        }

        return nil
    }

    /// Gets the last N business days from a given date (walking backwards)
    /// If the given date is a weekend/market closure, starts from the previous business day
    /// - Parameters:
    ///   - count: Number of business days to retrieve
    ///   - date: The date to start from
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    public static func recentBusinessDays(count: Int, from date: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> [CalendarDate] {
        var dates: [CalendarDate] = []

        // Start from the most recent business day
        guard var current = previousBusinessDay(from: date, mic: mic, underlyingMIC: underlyingMIC) else {
            return []
        }

        // Collect the requested number of business days
        while dates.count < count {
            dates.append(current)

            guard let previous = current.previousDay else { break }
            current = previous

            // Skip to next business day
            while !isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
                guard let prev = current.previousDay else { return dates }
                current = prev
            }
        }

        return dates
    }

    // MARK: - Public API (Country-based)

    /// Checks if a CalendarDate falls on a business day for a specific country
    public static func isBusinessDay(_ date: CalendarDate, country: Country) -> Bool {
        guard date.isWeekday else { return false }
        return !isMarketClosed(date, country: country)
    }

    /// Returns all business days for a specific country in the given date range
    public static func allBusinessDays(from start: CalendarDate, to end: CalendarDate, country: Country) -> [CalendarDate] {
        var dates: [CalendarDate] = []
        var current = start

        while current <= end {
            if isBusinessDay(current, country: country) {
                dates.append(current)
            }

            guard let next = current.nextDay else { break }
            current = next
        }

        return dates
    }

    // MARK: - Public API (Business Day Count)

    /// Returns the number of business days in the given date range (inclusive)
    /// - Parameters:
    ///   - start: Start date
    ///   - end: End date
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    public static func businessDayCount(from start: CalendarDate, to end: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> Int {
        var count = 0
        var current = start
        while current <= end {
            if isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
                count += 1
            }
            guard let next = current.nextDay else { break }
            current = next
        }
        return count
    }

    /// Returns the number of business days in the given date range for a specific country (inclusive)
    public static func businessDayCount(from start: CalendarDate, to end: CalendarDate, country: Country) -> Int {
        var count = 0
        var current = start
        while current <= end {
            if isBusinessDay(current, country: country) {
                count += 1
            }
            guard let next = current.nextDay else { break }
            current = next
        }
        return count
    }

    // MARK: - Public API (Forward Navigation)

    /// Finds the next business day after the given date
    /// If the given date is a business day, returns the next one (not the same day)
    /// - Parameters:
    ///   - date: The date to start from
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    public static func nextBusinessDay(from date: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> CalendarDate? {
        guard var current = date.nextDay else { return nil }

        // Walk forward to find the next business day
        for _ in 0 ..< 30 { // Safety limit
            if isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
                return current
            }
            guard let next = current.nextDay else { return nil }
            current = next
        }

        return nil
    }

    /// Adds a number of business days to a date, skipping weekends and holidays
    /// - Parameters:
    ///   - count: Number of business days to add (must be positive)
    ///   - date: The date to start from
    ///   - mic: Optional MIC code for market-specific closures
    ///   - underlyingMIC: Optional MIC code for the underlying asset's market
    /// - Returns: The date after adding the specified number of business days, or nil if calculation fails
    public static func addBusinessDays(_ count: Int, from date: CalendarDate, mic: MIC? = nil, underlyingMIC: MIC? = nil) -> CalendarDate? {
        guard count > 0 else { return date }

        var remaining = count
        var current = date

        while remaining > 0 {
            guard let next = current.nextDay else { return nil }
            current = next
            if isBusinessDay(current, mic: mic, underlyingMIC: underlyingMIC) {
                remaining -= 1
            }
        }

        return current
    }

    // MARK: - Public Utility

    /// Returns the country for a given MIC code
    public static func country(for mic: MIC) -> Country? {
        countryFromMIC(mic)
    }

    // MARK: - Market Closure Logic

    /// Checks if the market is closed on a given date for a country
    private static func isMarketClosed(_ date: CalendarDate, country: Country) -> Bool {
        // Use cached market closures for this year and country
        let closures = marketClosuresForYear(date.year, country: country)
        return closures.contains(date)
    }

    /// Gets all market closure dates for a given year and country (cached)
    private static func marketClosuresForYear(_ year: Int, country: Country) -> Set<CalendarDate> {
        let key = CacheKey(year: year, country: country)

        // Check cache first with lock
        if let cached = cache.withLock({ $0.closures[key] }) {
            return cached
        }

        // Calculate and cache
        let closures = marketClosuresForYearUnsafe(year, country: country)

        cache.withLock { $0.closures[key] = closures }

        return closures
    }

    /// Calculates market closures without caching (internal use only)
    private static func marketClosuresForYearUnsafe(_ year: Int, country: Country) -> Set<CalendarDate> {
        let rules = marketClosureRules(for: country)
        var closures = Set<CalendarDate>()

        // Pre-calculate Easter once for the year (used by multiple closures)
        let easter = MarketClosureRule.calculateEaster(year: year)

        // Calculate each closure date directly instead of checking every day
        for rule in rules {
            if let dates = rule.calculateDates(for: year, preCalculatedEaster: easter) {
                closures.formUnion(dates)
            }
        }

        return closures
    }

    /// Finds the holiday name for a given date and country, if it's a market closure
    private static func findHolidayName(_ date: CalendarDate, country: Country) -> String? {
        let rules = marketClosureRules(for: country)
        let easter = MarketClosureRule.calculateEaster(year: date.year)

        for rule in rules {
            if rule.matches(date, preCalculatedEaster: easter) {
                return rule.name
            }
        }

        return nil
    }

    // MARK: - MIC-Based Market Closure Logic

    /// Checks if market is closed for a MIC (handles registered, country-mapped, and exchange-specific MICs)
    private static func isMarketClosed(_ date: CalendarDate, mic: MIC) -> Bool {
        // Check registered calendar first
        if let calendar = exchangeCalendar(for: mic) {
            let closures = registeredCalendarClosures(date.year, mic: mic, calendar: calendar)
            return closures.contains(date)
        }

        if let country = country(for: mic) {
            return isMarketClosed(date, country: country)
        }
        let closures = exchangeClosuresForYear(date.year, mic: mic)
        return closures.contains(date)
    }

    /// Finds holiday name for a MIC (handles registered, country-mapped, and exchange-specific MICs)
    private static func findHolidayName(_ date: CalendarDate, mic: MIC) -> String? {
        // Check registered calendar first
        if let calendar = exchangeCalendar(for: mic) {
            let easter = MarketClosureRule.calculateEaster(year: date.year)
            for rule in calendar.closureRules {
                if rule.matches(date, preCalculatedEaster: easter) {
                    return rule.name
                }
            }
            return nil
        }

        if let country = country(for: mic) {
            return findHolidayName(date, country: country)
        }
        guard let rules = exchangeClosureRules(for: mic) else { return nil }
        let easter = MarketClosureRule.calculateEaster(year: date.year)
        for rule in rules {
            if rule.matches(date, preCalculatedEaster: easter) {
                return rule.name
            }
        }
        return nil
    }

    /// Returns true if two MICs share the same closure rules (same MIC or same country)
    private static func sharesClosureRules(_ mic1: MIC?, _ mic2: MIC) -> Bool {
        guard let mic1 else { return false }
        if mic1 == mic2 { return true }
        if let c1 = country(for: mic1), let c2 = country(for: mic2), c1 == c2 { return true }
        return false
    }

    /// Gets all closure dates for a registered exchange calendar (cached)
    private static func registeredCalendarClosures(_ year: Int, mic: MIC, calendar: ExchangeCalendar) -> Set<CalendarDate> {
        let key = ExchangeCacheKey(year: year, mic: mic.code)

        if let cached = cache.withLock({ $0.exchangeClosures[key] }) {
            return cached
        }

        var closures = Set<CalendarDate>()
        let easter = MarketClosureRule.calculateEaster(year: year)
        for rule in calendar.closureRules {
            if let dates = rule.calculateDates(for: year, preCalculatedEaster: easter) {
                closures.formUnion(dates)
            }
        }

        cache.withLock { $0.exchangeClosures[key] = closures }
        return closures
    }

    /// Gets all exchange closure dates for a given year and MIC (cached)
    private static func exchangeClosuresForYear(_ year: Int, mic: MIC) -> Set<CalendarDate> {
        let key = ExchangeCacheKey(year: year, mic: mic.code)

        if let cached = cache.withLock({ $0.exchangeClosures[key] }) {
            return cached
        }

        guard let rules = exchangeClosureRules(for: mic) else {
            return []
        }

        var closures = Set<CalendarDate>()
        let easter = MarketClosureRule.calculateEaster(year: year)
        for rule in rules {
            if let dates = rule.calculateDates(for: year, preCalculatedEaster: easter) {
                closures.formUnion(dates)
            }
        }

        cache.withLock { $0.exchangeClosures[key] = closures }
        return closures
    }

    /// Returns exchange-specific closure rules for MICs that don't map to a single country.
    static func exchangeClosureRules(for mic: MIC) -> [MarketClosureRule]? {
        switch mic.code {
        case "XEUE": eurexExchangeClosureRules
        default: nil
        }
    }

    // MARK: - Built-in Trading Sessions

    /// Returns the trading session for built-in exchange calendars
    private static func builtInTradingSession(on date: CalendarDate, mic: MIC) -> TradingSession? {
        let easter = MarketClosureRule.calculateEaster(year: date.year)

        switch mic.code {
        case "XSTO", "FNSE", "XNGM", "SSME", "XSAT":
            // Stockholm: 09:00-17:30, half-days at 13:00
            let shortenedRules: [MarketClosureRule] = [
                .fixed(month: 1, day: 5, name: "Day before Epiphany"),
                .easterOffset(days: -3, name: "Maundy Thursday"),
                .fixed(month: 4, day: 30, name: "Walpurgis Night"),
                .easterOffset(days: 38, name: "Day before Ascension"),
                .fixed(month: 11, day: 1, name: "All Saints' Eve Approx"),
                .fixed(month: 12, day: 23, name: "Day before Christmas Eve"),
                .fixed(month: 12, day: 30, name: "Day before New Year's Eve"),
            ]
            for rule in shortenedRules {
                if rule.matches(date, preCalculatedEaster: easter) {
                    return TradingSession(open: TimeOfDay(hour: 9, minute: 0), close: TimeOfDay(hour: 13, minute: 0))
                }
            }
            return TradingSession(open: TimeOfDay(hour: 9, minute: 0), close: TimeOfDay(hour: 17, minute: 30))

        case "XNYS", "XNAS", "ARCX", "BATS", "IEXG":
            // NYSE/NASDAQ: 09:30-16:00, half-days at 13:00
            let shortenedRules: [MarketClosureRule] = [
                .dayAfterNthWeekday(month: 11, nth: 4, weekday: 5, name: "Black Friday"),
                .fixed(month: 12, day: 24, name: "Christmas Eve"),
            ]
            for rule in shortenedRules {
                if rule.matches(date, preCalculatedEaster: easter) {
                    return TradingSession(open: TimeOfDay(hour: 9, minute: 30), close: TimeOfDay(hour: 13, minute: 0))
                }
            }
            return TradingSession(open: TimeOfDay(hour: 9, minute: 30), close: TimeOfDay(hour: 16, minute: 0))

        case "XLON", "XLOM", "XOFF", "AIMX":
            // London: 08:00-16:30, half-days at 12:30
            let shortenedRules: [MarketClosureRule] = [
                .fixed(month: 12, day: 24, name: "Christmas Eve"),
                .fixed(month: 12, day: 31, name: "New Year's Eve"),
            ]
            for rule in shortenedRules {
                if rule.matches(date, preCalculatedEaster: easter) {
                    return TradingSession(open: TimeOfDay(hour: 8, minute: 0), close: TimeOfDay(hour: 12, minute: 30))
                }
            }
            return TradingSession(open: TimeOfDay(hour: 8, minute: 0), close: TimeOfDay(hour: 16, minute: 30))

        default:
            return nil
        }
    }

    // MARK: - Market Closure Rules

    /// Returns market closure rules for a specific country
    public static func marketClosureRules(for country: Country) -> [MarketClosureRule] {
        switch country {
        case .us:
            usMarketClosureRules
        case .gb:
            ukMarketClosureRules
        case .se:
            swedishMarketClosureRules
        case .no:
            norwegianMarketClosureRules
        case .dk:
            danishMarketClosureRules
        case .fi:
            finnishMarketClosureRules
        case .is:
            icelandicMarketClosureRules
        case .de:
            germanMarketClosureRules
        case .fr:
            frenchMarketClosureRules
        case .nl:
            dutchMarketClosureRules
        case .be:
            belgianMarketClosureRules
        case .it:
            italianMarketClosureRules
        case .es:
            spanishMarketClosureRules
        case .pt:
            portugueseMarketClosureRules
        case .lu:
            luxembourgMarketClosureRules
        case .ch:
            swissMarketClosureRules
        case .at:
            austrianMarketClosureRules
        case .pl:
            polishMarketClosureRules
        case .hu:
            hungarianMarketClosureRules
        case .cz:
            czechMarketClosureRules
        case .ie:
            irishMarketClosureRules
        case .gr:
            greekMarketClosureRules
        case .jp:
            japaneseMarketClosureRules
        case .au:
            australianMarketClosureRules
        case .ca:
            canadianMarketClosureRules
        default:
            universalMarketClosureRules
        }
    }

    // Universal market closures (observed by most markets)
    static let universalMarketClosureRules: [MarketClosureRule] = [
        .fixed(month: 1, day: 1, name: "New Year's Day"),
        .fixed(month: 12, day: 25, name: "Christmas Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .easterOffset(days: 1, name: "Easter Monday"),
    ]

    // US market closures (NYSE/NASDAQ)
    static let usMarketClosureRules: [MarketClosureRule] = [
        .fixedWithObserved(month: 1, day: 1, name: "New Year's Day"),
        .nthWeekday(month: 1, nth: 3, weekday: 2, name: "MLK Day"),
        .nthWeekday(month: 2, nth: 3, weekday: 2, name: "Presidents Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .lastWeekday(month: 5, weekday: 2, name: "Memorial Day"),
        .fixedWithObservedFromYear(month: 6, day: 19, fromYear: 2_022, name: "Juneteenth"),
        .fixedWithObserved(month: 7, day: 4, name: "Independence Day"),
        .nthWeekday(month: 9, nth: 1, weekday: 2, name: "Labor Day"),
        .nthWeekday(month: 11, nth: 4, weekday: 5, name: "Thanksgiving"),
        .fixedWithObserved(month: 12, day: 25, name: "Christmas Day"),
    ]

    static let ukMarketClosureRules: [MarketClosureRule] = [
        .fixedWithSubstitute(month: 1, day: 1, name: "New Year's Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .easterOffset(days: 1, name: "Easter Monday"),
        .nthWeekday(month: 5, nth: 1, weekday: 2, name: "Early May Bank Holiday"),
        .lastWeekday(month: 5, weekday: 2, name: "Spring Bank Holiday"),
        .lastWeekday(month: 8, weekday: 2, name: "Summer Bank Holiday"),
        .christmasBoxingDayCascade,
        .oneOff(year: 2_020, month: 5, day: 8, name: "VE Day 75th Anniversary"),
        .oneOff(year: 2_012, month: 6, day: 4, name: "Queen's Diamond Jubilee"),
        .oneOff(year: 2_012, month: 6, day: 5, name: "Queen's Diamond Jubilee"),
        .oneOff(year: 2_022, month: 6, day: 2, name: "Queen's Platinum Jubilee"),
        .oneOff(year: 2_022, month: 6, day: 3, name: "Queen's Platinum Jubilee"),
        .oneOff(year: 2_022, month: 9, day: 19, name: "Queen Elizabeth II State Funeral"),
        .oneOff(year: 2_023, month: 5, day: 8, name: "King Charles III Coronation"),
    ]

    static let swedishMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 1, day: 6, name: "Epiphany"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .fixed(month: 6, day: 6, name: "National Day of Sweden"),
        .midsummer(name: "Midsummer"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let norwegianMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .easterOffset(days: -3, name: "Maundy Thursday"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 5, day: 17, name: "Constitution Day"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .easterOffset(days: 50, name: "Whit Monday"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let danishMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .easterOffset(days: -3, name: "Maundy Thursday"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .easterOffset(days: 40, name: "Day after Ascension Day"),
        .fixed(month: 6, day: 5, name: "Constitution Day"),
        .easterOffset(days: 50, name: "Whit Monday"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
        .easterOffsetUntilYear(days: 26, untilYear: 2_023, name: "Great Prayer Day"),
    ]

    static let finnishMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 1, day: 6, name: "Epiphany"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .midsummer(name: "Midsummer"),
        .fixed(month: 12, day: 6, name: "Independence Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let icelandicMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .easterOffset(days: -3, name: "Maundy Thursday"),
        .easterOffset(days: 26, name: "First Day of Summer"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .easterOffset(days: 50, name: "Whit Monday"),
        .fixed(month: 6, day: 17, name: "Icelandic National Day"),
        .nthWeekday(month: 8, nth: 1, weekday: 2, name: "Commerce Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let germanMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .easterOffsetUntilYear(days: 50, untilYear: 2_021, name: "Whit Monday"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let frenchMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
    ]

    static let dutchMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
    ]

    static let belgianMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
    ]

    static let italianMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 8, day: 15, name: "Assumption Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let spanishMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
        .oneOff(year: 2_021, month: 12, day: 24, name: "Christmas Eve"),
        .oneOff(year: 2_021, month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let portugueseMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
    ]

    static let luxembourgMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 5, day: 9, name: "Europe Day"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .easterOffset(days: 50, name: "Whit Monday"),
        .fixed(month: 6, day: 23, name: "National Day"),
        .fixed(month: 8, day: 15, name: "Assumption Day"),
        .fixed(month: 11, day: 1, name: "All Saints' Day"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
    ]

    static let swissMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 1, day: 2, name: "Berchtold's Day"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .easterOffset(days: 39, name: "Ascension Day"),
        .easterOffset(days: 50, name: "Whit Monday"),
        .fixed(month: 8, day: 1, name: "National Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let austrianMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .easterOffsetUntilYear(days: 50, untilYear: 2_022, name: "Whit Monday"),
        .fixed(month: 10, day: 26, name: "National Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let polishMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 1, day: 6, name: "Epiphany"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 5, day: 3, name: "Constitution Day"),
        .easterOffset(days: 60, name: "Corpus Christi"),
        .fixed(month: 8, day: 15, name: "Assumption Day"),
        .fixed(month: 11, day: 1, name: "All Saints' Day"),
        .fixed(month: 11, day: 11, name: "Independence Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let hungarianMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixedWithBridge(month: 3, day: 15, name: "1848 Revolution Day"),
        .fixedWithBridge(month: 5, day: 1, name: "Labour Day"),
        .easterOffset(days: 50, name: "Whit Monday"),
        .fixedWithBridge(month: 8, day: 20, name: "St. Stephen's Day"),
        .fixedWithBridge(month: 10, day: 23, name: "1956 Revolution Day"),
        .fixedWithBridge(month: 11, day: 1, name: "All Saints' Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let czechMarketClosureRules: [MarketClosureRule] = universalMarketClosureRules + [
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 5, day: 8, name: "Victory Day"),
        .fixed(month: 7, day: 5, name: "Saints Cyril and Methodius Day"),
        .fixed(month: 7, day: 6, name: "Jan Hus Day"),
        .fixed(month: 9, day: 28, name: "Statehood Day"),
        .fixed(month: 10, day: 28, name: "Independence Day"),
        .fixed(month: 11, day: 17, name: "Freedom and Democracy Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 26, name: "St. Stephen's Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]

    static let irishMarketClosureRules: [MarketClosureRule] = [
        .fixedWithSubstitute(month: 1, day: 1, name: "New Year's Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .easterOffset(days: 1, name: "Easter Monday"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .nthWeekday(month: 5, nth: 1, weekday: 2, name: "May Bank Holiday"),
        .christmasBoxingDayCascade,
    ]

    static let greekMarketClosureRules: [MarketClosureRule] = [
        .fixed(month: 1, day: 1, name: "New Year's Day"),
        .fixed(month: 1, day: 6, name: "Epiphany"),
        .fixed(month: 3, day: 25, name: "Independence Day"),
        .fixedWithSubstitute(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 8, day: 15, name: "Assumption Day"),
        .fixed(month: 10, day: 28, name: "Ochi Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 25, name: "Christmas Day"),
        .fixed(month: 12, day: 26, name: "Boxing Day"),
        .easterOffset(days: -2, name: "Western Good Friday"),
        .easterOffset(days: 1, name: "Western Easter Monday"),
        .orthodoxEasterOffset(days: -48, name: "Clean Monday"),
        .orthodoxEasterOffset(days: -2, name: "Orthodox Good Friday"),
        .orthodoxEasterOffset(days: 1, name: "Orthodox Easter Monday"),
        .orthodoxEasterOffset(days: 50, name: "Orthodox Whit Monday"),
    ]

    static let japaneseMarketClosureRules: [MarketClosureRule] = [
        .fixed(month: 1, day: 1, name: "New Year's Day"),
        .fixed(month: 1, day: 2, name: "Bank Holiday"),
        .fixed(month: 1, day: 3, name: "Bank Holiday"),
        .nthWeekday(month: 1, nth: 2, weekday: 2, name: "Coming of Age Day"),
        .nthWeekday(month: 7, nth: 3, weekday: 2, name: "Marine Day"),
        .nthWeekday(month: 9, nth: 3, weekday: 2, name: "Respect for the Aged Day"),
        .nthWeekday(month: 10, nth: 2, weekday: 2, name: "Sports Day"),
        .fixedWithJapaneseSubstitute(month: 2, day: 11, name: "National Foundation Day"),
        .fixedWithJapaneseSubstitute(month: 2, day: 23, name: "Emperor's Birthday"),
        .fixedWithJapaneseSubstitute(month: 4, day: 29, name: "Showa Day"),
        .fixedWithJapaneseSubstitute(month: 5, day: 3, name: "Constitution Memorial Day"),
        .fixedWithJapaneseSubstitute(month: 5, day: 4, name: "Greenery Day"),
        .fixedWithJapaneseSubstitute(month: 5, day: 5, name: "Children's Day"),
        .fixedWithJapaneseSubstitute(month: 8, day: 11, name: "Mountain Day"),
        .fixedWithJapaneseSubstitute(month: 11, day: 3, name: "Culture Day"),
        .fixedWithJapaneseSubstitute(month: 11, day: 23, name: "Labor Thanksgiving Day"),
        .japaneseVernalEquinox(name: "Vernal Equinox Day"),
        .japaneseAutumnalEquinox(name: "Autumnal Equinox Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
        .oneOff(year: 2_021, month: 7, day: 22, name: "Marine Day (Olympics)"),
        .oneOff(year: 2_021, month: 7, day: 23, name: "Sports Day (Olympics)"),
        .oneOff(year: 2_021, month: 8, day: 9, name: "Mountain Day (Olympics)"),
    ]

    static let australianMarketClosureRules: [MarketClosureRule] = [
        .fixedWithSubstitute(month: 1, day: 1, name: "New Year's Day"),
        .fixedWithSubstitute(month: 1, day: 26, name: "Australia Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .easterOffset(days: 1, name: "Easter Monday"),
        .fixed(month: 4, day: 25, name: "Anzac Day"),
        .nthWeekday(month: 6, nth: 2, weekday: 2, name: "King's Birthday"),
        .christmasBoxingDayCascade,
        .oneOff(year: 2_022, month: 9, day: 22, name: "Queen Elizabeth II Mourning"),
    ]

    static let canadianMarketClosureRules: [MarketClosureRule] = [
        .fixedWithSubstitute(month: 1, day: 1, name: "New Year's Day"),
        .nthWeekday(month: 2, nth: 3, weekday: 2, name: "Family Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .victoriaDay(name: "Victoria Day"),
        .fixedWithSubstitute(month: 7, day: 1, name: "Canada Day"),
        .nthWeekday(month: 8, nth: 1, weekday: 2, name: "Civic Holiday"),
        .nthWeekday(month: 9, nth: 1, weekday: 2, name: "Labour Day"),
        .nthWeekday(month: 10, nth: 2, weekday: 2, name: "Thanksgiving"),
        .christmasBoxingDayCascade,
    ]

    // MARK: - Exchange-Specific Closure Rules

    static let eurexExchangeClosureRules: [MarketClosureRule] = [
        .fixed(month: 1, day: 1, name: "New Year's Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .easterOffset(days: 1, name: "Easter Monday"),
        .fixed(month: 5, day: 1, name: "Labour Day"),
        .fixed(month: 12, day: 24, name: "Christmas Eve"),
        .fixed(month: 12, day: 25, name: "Christmas Day"),
        .fixed(month: 12, day: 31, name: "New Year's Eve"),
    ]
}
