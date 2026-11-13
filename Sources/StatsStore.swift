import Foundation

/// Owns the log scanner and publishes aggregated 7-day token/cost stats.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var stats: UsageStats?
    @Published private(set) var isScanning = false

    private let scanner = LogScanner()
    private var pricing: PricingTable?
    private var pricingLoadedAt: Date?
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Config.statsRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refreshIfStale() {
        let age = stats.map { Date().timeIntervalSince($0.scannedAt) } ?? .infinity
        if age > Config.statsStaleAfter { refresh() }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task { @MainActor in
            let table = await currentPricing()
            let now = Date()
            let cutoff = Calendar.current.date(
                byAdding: .day, value: -(Config.statsRangeDays - 1), to: Calendar.current.startOfDay(for: now)
            ) ?? now
            let files = await scanner.scan(modifiedSince: cutoff)
            let result = await Task.detached(priority: .utility) {
                StatsAggregator.build(files: files, pricing: table, rangeDays: Config.statsRangeDays, now: now)
            }.value
            stats = result
            isScanning = false
        }
    }

    private func currentPricing() async -> PricingTable {
        if let pricing, let loaded = pricingLoadedAt, Date().timeIntervalSince(loaded) < 24 * 60 * 60 {
            return pricing
        }
        let table = await PricingLoader.load()
        pricing = table
        pricingLoadedAt = Date()
        return table
    }
}
