// swift-tools-version: 6.2
import PackageDescription

let package: Package = .init(
    name: "TradingCalendar",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "TradingCalendar",
            targets: ["TradingCalendar"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "TradingCalendar"
        ),
        .testTarget(
            name: "TradingCalendarTests",
            dependencies: [
                "TradingCalendar",
            ],
            exclude: ["Fixtures"]
        ),
        .executableTarget(
            name: "TradingCalendarBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                "TradingCalendar",
            ],
            path: "Benchmarks/TradingCalendarBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
            ]
        ),
    ]
)
