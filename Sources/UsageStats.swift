import Foundation

/// Token counts for one bucket. `input` is uncached input only.
struct TokenCounts: Equatable {
    let input: Int
    let cacheRead: Int
    let cacheWrite: Int
    let output: Int

    static let zero = TokenCounts(input: 0, cacheRead: 0, cacheWrite: 0, output: 0)

    var total: Int { input + cacheRead + cacheWrite + output }

    func adding(_ other: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: input + other.input,
            cacheRead: cacheRead + other.cacheRead,
            cacheWrite: cacheWrite + other.cacheWrite,
            output: output + other.output
        )
    }
}

struct BucketKey: Hashable {
    let model: String
    let day: Date
}

/// Immutable result of scanning one session log file.
struct ScannedFile {
    let provider: Provider
    let sessionKey: String
    let buckets: [BucketKey: TokenCounts]
}

struct ProviderTotals: Equatable, Identifiable {
    let provider: Provider
    let sessions: Int
    let tokens: Int
    let cost: Double
    var id: Provider { provider }
}

struct ModelTotals: Equatable, Identifiable {
    let provider: Provider
    let model: String
    let tokens: Int
    let cost: Double
    var id: String { "\(provider.rawValue):\(model)" }
}

struct DayTotals: Equatable, Identifiable {
    let day: Date
    let provider: Provider
    let tokens: Int
    var id: String { "\(provider.rawValue):\(day.timeIntervalSince1970)" }
}

struct UsageStats: Equatable {
    let rangeDays: Int
    let providers: [ProviderTotals]
    let models: [ModelTotals]
    let days: [DayTotals]
    let totals: TokenCounts
    let scannedAt: Date

    var totalTokens: Int { providers.reduce(0) { $0 + $1.tokens } }
    var totalSessions: Int { providers.reduce(0) { $0 + $1.sessions } }
    var totalCost: Double { providers.reduce(0) { $0 + $1.cost } }
}
