# TradingCalendar

A standalone Swift library for determining exchange trading days across global markets. Handles weekends and market-specific holidays for 24 countries and 100+ MIC codes, with configurable exchange calendars and trading sessions — all validated against real Yahoo Finance data.

**Zero proprietary dependencies.** This is the open-source successor to `package-trading-calendar`. See [Differences from the internal library](#differences-from-the-internal-library) below.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ordo-one/trading-calendar", from: "1.0.0"),
]
```

Then add `"TradingCalendar"` to your target's dependencies:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "TradingCalendar", package: "trading-calendar"),
    ]
)
```

## Usage

All API is exposed as static methods on the `TradingCalendar` enum.

### Checking business days

```swift
import TradingCalendar

// Weekend-only check (no MIC)
TradingCalendar.isBusinessDay(date)

// Market-aware check (skips weekends + market holidays)
TradingCalendar.isBusinessDay(date, mic: .XSTO)

// Country-based check
TradingCalendar.isBusinessDay(date, country: .se)

// Derivative with underlying on a different market
TradingCalendar.isBusinessDay(date, mic: .XEUE, underlyingMIC: .XETR)
```

### Why is a day closed?

```swift
let reason = TradingCalendar.nonBusinessDayReason(date, mic: .XNYS)
switch reason {
case .weekend:             // Saturday or Sunday
case .holiday(let name):   // e.g. "Thanksgiving"
case .businessDay:         // It's open
}
```

### Navigation

```swift
// Most recent business day on or before the given date
TradingCalendar.previousBusinessDay(from: date, mic: .XLON)

// Next business day strictly after the given date
TradingCalendar.nextBusinessDay(from: date, mic: .XLON)

// Add N business days (e.g. T+3 settlement)
TradingCalendar.addBusinessDays(3, from: tradeDate, mic: .XSTO)
```

### Ranges and counting

```swift
// All business days in a range (inclusive)
let days = TradingCalendar.allBusinessDays(from: start, to: end, mic: .XETR)

// Count of business days in a range (inclusive)
let count = TradingCalendar.businessDayCount(from: start, to: end, mic: .XETR)

// Last N business days walking backwards
let recent = TradingCalendar.recentBusinessDays(count: 10, from: date, mic: .XSTO)
```

### Trading sessions

```swift
// Returns the trading session for a date (nil if closed, shortened on half-days)
let session = TradingCalendar.tradingSession(on: date, mic: .XNYS)
// session?.open  → TimeOfDay(hour: 9, minute: 30)
// session?.close → TimeOfDay(hour: 16, minute: 0)
```

### Custom exchange calendars

Register a custom calendar at runtime — overrides any built-in calendar for that MIC:

```swift
let calendar = ExchangeCalendar(
    name: "My Exchange",
    closureRules: [
        .fixed(month: 1, day: 1, name: "New Year's Day"),
        .easterOffset(days: -2, name: "Good Friday"),
        .fixed(month: 12, day: 25, name: "Christmas Day"),
    ],
    session: TradingSession(
        open: TimeOfDay(hour: 9, minute: 0),
        close: TimeOfDay(hour: 17, minute: 0)
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

TradingCalendar.register(calendar, for: MIC("XMYEX"))
```

### Loading calendars from JSON

All types are `Codable` — calendars can be loaded from JSON files without recompilation:

```swift
let data = try Data(contentsOf: configURL)
try TradingCalendar.register(from: data, for: .XETR)
```

Example JSON:

```json
{
  "name": "Custom XETR",
  "closureRules": [
    {"type": "fixed", "month": 1, "day": 1, "name": "New Year's Day"},
    {"type": "easterOffset", "days": -2, "name": "Good Friday"},
    {"type": "fixed", "month": 12, "day": 25, "name": "Christmas Day"}
  ],
  "session": {
    "open": {"hour": 9, "minute": 0},
    "close": {"hour": 17, "minute": 30}
  }
}
```

### Utility

```swift
// Look up country for a MIC code
let country = TradingCalendar.country(for: .XSTO) // .se

// Pre-warm the holiday cache (optional, called once at startup)
TradingCalendar.prewarmCache()
```

## Types

The library defines its own lightweight types — no Foundation `Calendar` or `Date` needed for core operations:

| Type | Description |
|------|-------------|
| `CalendarDate` | Year/month/day with pure Gregorian arithmetic (weekday, nextDay, addingDays) |
| `MIC` | String-based ISO 10383 Market Identifier Code (2,272 active codes as static constants) |
| `Country` | ISO 3166-1 alpha-2 enum (249 countries with human-readable names) |
| `MarketClosureRule` | Public enum with 19 rule types for modeling holidays |
| `ExchangeCalendar` | Configurable calendar with closure rules, sessions, and half-days |
| `TradingSession` | Open/close times as `TimeOfDay` |
| `NonBusinessDayReason` | Why a day is closed: `.weekend`, `.holiday(name:)`, or `.businessDay` |

All types conform to `Sendable` and `Codable`.

## Supported markets

| Country | MICs | Exchange |
|---------|------|----------|
| US | XNYS, XNAS, XASE, BATS, IEXG, ARCX, XPHL, XBOS, XCIS, XCHI, EDGA, EDGX, MEMX | NYSE, NASDAQ, etc. |
| GB | XLON, CHIX | London, CBOE Europe CXE |
| SE | XSTO, SSME, XNGM | Nasdaq Stockholm, Spotlight, NGM |
| NO | XOSL, MERK, XOAS | Oslo Bors, Merkur, Oslo Axess |
| DK | XCSE | Nasdaq Copenhagen |
| FI | XHEL | Nasdaq Helsinki |
| IS | XICE | Nasdaq Iceland |
| DE | XETR, XFRA, XBER, XDUS, XHAM, XHAN, XMUN, XSTU | Xetra, Frankfurt, etc. |
| FR | XPAR, ALXP | Euronext Paris, Alternext |
| NL | XAMS | Euronext Amsterdam |
| BE | XBRU | Euronext Brussels |
| IT | MTAA, ETLX | Borsa Italiana, EuroTLX |
| ES | XMAD, XBAR, XVAL, XBIL | BME (Madrid, Barcelona, etc.) |
| PT | XLIS | Euronext Lisbon |
| LU | XLUX | Luxembourg |
| CH | XSWX, XBER | SIX Swiss Exchange |
| AT | XWBO | Wiener Borse |
| PL | XWAR | GPW Warsaw |
| HU | XBUD | BSE Budapest |
| CZ | XPRA | PSE Prague |
| IE | XDUB | Euronext Dublin |
| GR | ASEX | Athens Stock Exchange |
| JP | XTKS, XOSE, XNGO, XFKA, XSAP | Tokyo, Osaka, etc. |
| AU | XASX | ASX |
| CA | XTSE, XTSX, XMOD, XCNQ, NEOE, PURE | TSX, TSXV, etc. |
| EU | XEUE | Eurex (exchange-wide holidays, plus underlying market support) |

MICs not in this table fall back to a universal calendar (weekends + New Year, Christmas, Good Friday, Easter Monday).

## Holiday rule types

The library uses a rule-based engine supporting:

- **Fixed dates** — e.g. Christmas (Dec 25), with optional observed-day or substitute-day rules
- **Nth weekday** — e.g. 3rd Monday of January (MLK Day)
- **Last weekday** — e.g. last Monday of May (Memorial Day)
- **Easter-relative** — e.g. Good Friday (Easter - 2), with Orthodox Easter support
- **Country-specific** — Midsummer (Sweden), Victoria Day (Canada), bridge days (Hungary), Japanese substitute holidays, Christmas/Boxing Day cascading substitutes
- **One-off events** — e.g. Queen's Platinum Jubilee, Tokyo Olympics date moves
- **Time-bounded rules** — e.g. Great Prayer Day (Denmark, abolished 2024), Whit Monday (Germany, dropped from Xetra 2022)

## Differences from the internal library

This library (`trading-calendar`) is the open-source replacement for `package-trading-calendar`. The core holiday logic and market coverage are identical. Here is what changed:

### Removed: Ordo SDK dependency

`package-trading-calendar` imports `Ordo` for `CalendarDate`, `MIC`, `Country`, and `Instrument`. This library defines its own types from official standards (ISO 10383, ISO 3166-1), making it usable by anyone without access to the Ordo SDK.

The `isBusinessDay(_:instrument:)` convenience method that accepted an `Ordo.Instrument` has been removed — the plugin handles this composition directly.

### Added: Own types from ISO standards

| Type | `package-trading-calendar` | `trading-calendar` |
|------|---------------------------|-------------------|
| `CalendarDate` | From Ordo SDK | Own type, pure Gregorian arithmetic |
| `MIC` | From Ordo SDK (UInt16-backed) | Own type, string-based, 2,272 ISO 10383 codes |
| `Country` | From Ordo SDK (UInt16-backed) | Own type, String raw value, 249 ISO 3166-1 codes |

### Added: Configurable exchange calendars

`package-trading-calendar` has all calendars hardcoded — adding or modifying a calendar requires changing source code and recompiling.

`trading-calendar` adds:
- `ExchangeCalendar` — a Codable struct combining closure rules, trading session hours, and half-day schedules
- `TradingCalendar.register(_:for:)` — register custom calendars at runtime
- `TradingCalendar.register(from:for:)` — load calendars from JSON
- `TradingCalendar.tradingSession(on:mic:)` — query open/close times (normal or shortened)

### Added: Public `MarketClosureRule`

The `MarketClosureRule` enum (19 rule types) is now `public` with full `Codable` support, so clients can compose their own holiday rules programmatically or via JSON.

### Added: Codable support

All types (`CalendarDate`, `MIC`, `Country`, `MarketClosureRule`, `ExchangeCalendar`, `TradingSession`, `TimeOfDay`) are `Codable`. Exchange calendars can be serialized to/from JSON for configuration-driven deployments.

### Unchanged

- All holiday rules and market coverage (24 countries, 100+ MICs)
- The static API surface (`isBusinessDay`, `nonBusinessDayReason`, `businessDayCount`, `addBusinessDays`, etc.)
- Performance characteristics (Mutex-based caching, pure-arithmetic date operations)
- Validation against Yahoo Finance data (49 tests, 26 markets)
