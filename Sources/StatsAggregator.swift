import Foundation

/// Pure function: scanned files + prices → display-ready stats for the last N calendar days.
enum StatsAggregator {
    static func build(files: [ScannedFile], pricing: PricingTable, rangeDays: Int, now: Date) -> UsageStats {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dayList = (0..<rangeDays).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let start = dayList.first ?? today

        var modelCounts: [ModelKey: TokenCounts] = [:]
        var dayTokens: [DayKey: Int] = [:]
        var sessions: [Provider: Set<String>] = [:]
        var totals = TokenCounts.zero

        for file in files {
            for (key, counts) in file.buckets where key.day >= start {
                let modelKey = ModelKey(provider: file.provider, model: key.model)
                modelCounts[modelKey] = (modelCounts[modelKey] ?? .zero).adding(counts)
                dayTokens[DayKey(provider: file.provider, day: key.day), default: 0] += counts.total
                sessions[file.provider, default: []].insert(file.sessionKey)
                totals = totals.adding(counts)
            }
        }

        let models = modelCounts
            .map { key, counts in
                ModelTotals(
                    provider: key.provider,
                    model: key.model,
                    tokens: counts.total,
                    cost: pricing.cost(model: key.model, counts: counts)
                )
            }
            .sorted { $0.tokens > $1.tokens }

        let providers = Provider.allCases.map { provider in
            let mine = models.filter { $0.provider == provider }
            return ProviderTotals(
                provider: provider,
                sessions: sessions[provider]?.count ?? 0,
                tokens: mine.reduce(0) { $0 + $1.tokens },
                cost: mine.reduce(0) { $0 + $1.cost }
            )
        }

        let days = Provider.allCases.flatMap { provider in
            dayList.map { day in
                DayTotals(day: day, provider: provider, tokens: dayTokens[DayKey(provider: provider, day: day)] ?? 0)
            }
        }

        return UsageStats(
            rangeDays: rangeDays,
            providers: providers,
            models: models,
            days: days,
            totals: totals,
            scannedAt: now
        )
    }

    private struct ModelKey: Hashable {
        let provider: Provider
        let model: String
    }

    private struct DayKey: Hashable {
        let provider: Provider
        let day: Date
    }
}
