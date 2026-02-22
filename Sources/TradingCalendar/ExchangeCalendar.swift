/// A time of day with hour and minute precision.
public struct TimeOfDay: Sendable, Equatable, Comparable, Hashable, Codable {
    public var hour: Int   // 0-23
    public var minute: Int // 0-59

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// A trading session defined by open and close times.
public struct TradingSession: Sendable, Equatable, Hashable, Codable {
    public var open: TimeOfDay
    public var close: TimeOfDay

    public init(open: TimeOfDay, close: TimeOfDay) {
        self.open = open
        self.close = close
    }
}

/// A shortened trading session triggered by a specific closure rule.
public struct ShortenedSession: Sendable, Codable {
    public var rule: MarketClosureRule
    public var session: TradingSession

    public init(rule: MarketClosureRule, session: TradingSession) {
        self.rule = rule
        self.session = session
    }
}

/// A complete exchange calendar with closure rules, normal trading session,
/// and optional shortened sessions for half-days.
public struct ExchangeCalendar: Sendable, Codable {
    public var name: String
    public var closureRules: [MarketClosureRule]
    public var session: TradingSession?
    public var shortenedSessions: [ShortenedSession]

    public init(
        name: String,
        closureRules: [MarketClosureRule],
        session: TradingSession? = nil,
        shortenedSessions: [ShortenedSession] = []
    ) {
        self.name = name
        self.closureRules = closureRules
        self.session = session
        self.shortenedSessions = shortenedSessions
    }
}
