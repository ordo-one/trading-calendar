import Benchmark
import TradingCalendar

// MARK: - Configuration

private nonisolated(unsafe) let defaultConfiguration: Benchmark.Configuration = {
    var config = Benchmark.Configuration()
    config.maxIterations = 100_000_000
    config.maxDuration = .seconds(2)
    config.scalingFactor = .kilo
    config.metrics = [.wallClock, .mallocCountTotal, .peakMemoryResident]
    return config
}()

// MARK: - Test Data

/// A known weekday (Wednesday, Feb 19, 2025)
private let sampleWeekday = CalendarDate(year: 2025, month: 2, day: 19)!

/// A known US holiday (Christmas Day 2025 = Thursday)
private let sampleHoliday = CalendarDate(year: 2025, month: 12, day: 25)!

/// A year range for business day counting (~1 year)
private let rangeStart = CalendarDate(year: 2025, month: 1, day: 1)!
private let rangeEnd = CalendarDate(year: 2025, month: 12, day: 31)!

/// A quarter range for business day counting
private let quarterStart = CalendarDate(year: 2025, month: 1, day: 1)!
private let quarterEnd = CalendarDate(year: 2025, month: 3, day: 31)!

// MARK: - Benchmarks

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = defaultConfiguration

    // MARK: isBusinessDay — weekday-only (no MIC)

    Benchmark("isBusinessDay_noMIC",
              closure: { benchmark in
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.isBusinessDay(sampleWeekday))
                  }
              } as Benchmark.BenchmarkClosure)

    // MARK: isBusinessDay — with MIC (cache hit path)

    Benchmark("isBusinessDay_XNYS",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.isBusinessDay(sampleWeekday, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("isBusinessDay_XSTO",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.isBusinessDay(sampleWeekday, mic: .XSTO))
                  }
              } as Benchmark.BenchmarkClosure)

    // MARK: nonBusinessDayReason

    Benchmark("nonBusinessDayReason_weekday",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.nonBusinessDayReason(sampleWeekday, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("nonBusinessDayReason_holiday",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.nonBusinessDayReason(sampleHoliday, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    // MARK: businessDayCount

    Benchmark("businessDayCount_quarter_noMIC",
              closure: { benchmark in
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.businessDayCount(from: quarterStart, to: quarterEnd))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("businessDayCount_quarter_XNYS",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.businessDayCount(from: quarterStart, to: quarterEnd, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("businessDayCount_year_XSTO",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.businessDayCount(from: rangeStart, to: rangeEnd, mic: .XSTO))
                  }
              } as Benchmark.BenchmarkClosure)

    // MARK: Navigation

    Benchmark("previousBusinessDay_XNYS",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.previousBusinessDay(from: sampleWeekday, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("nextBusinessDay_XNYS",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.nextBusinessDay(from: sampleWeekday, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("addBusinessDays_3_XNYS",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.addBusinessDays(3, from: sampleWeekday, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    Benchmark("addBusinessDays_10_XSTO",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.addBusinessDays(10, from: sampleWeekday, mic: .XSTO))
                  }
              } as Benchmark.BenchmarkClosure)

    // MARK: allBusinessDays

    Benchmark("allBusinessDays_quarter_XNYS",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.allBusinessDays(from: quarterStart, to: quarterEnd, mic: .XNYS))
                  }
              } as Benchmark.BenchmarkClosure)

    // MARK: prewarmCache

    Benchmark("prewarmCache_alreadyWarmed",
              closure: { benchmark in
                  TradingCalendar.prewarmCache()
                  for _ in benchmark.scaledIterations {
                      Benchmark.blackHole(TradingCalendar.prewarmCache())
                  }
              } as Benchmark.BenchmarkClosure)
}
