import Foundation

/// Per-token USD rates for one model.
struct ModelRate: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
}

/// LiteLLM-format price table. Unknown models cost 0 (shown as tokens only).
struct PricingTable {
    let rates: [String: ModelRate]

    static let empty = PricingTable(rates: [:])

    func cost(model: String, counts: TokenCounts) -> Double {
        guard let rate = lookup(model) else { return 0 }
        return Double(counts.input) * rate.input
            + Double(counts.output) * rate.output
            + Double(counts.cacheRead) * rate.cacheRead
            + Double(counts.cacheWrite) * rate.cacheWrite
    }

    private func lookup(_ model: String) -> ModelRate? {
        let undated = model.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        let candidates = [model, undated, "anthropic/\(model)", "openai/\(model)", "anthropic/\(undated)"]
        return candidates.lazy.compactMap { rates[$0] }.first
    }

    /// Accepts either a raw LiteLLM document or T3 Code's `{ "document": {...} }` wrapper.
    static func parse(_ data: Data) -> PricingTable? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let document = root["document"] as? [String: Any] ?? root
        var rates: [String: ModelRate] = [:]
        for (name, value) in document {
            guard
                let entry = value as? [String: Any],
                let input = (entry["input_cost_per_token"] as? NSNumber)?.doubleValue,
                let output = (entry["output_cost_per_token"] as? NSNumber)?.doubleValue
            else { continue }
            rates[name] = ModelRate(
                input: input,
                output: output,
                cacheRead: (entry["cache_read_input_token_cost"] as? NSNumber)?.doubleValue ?? input,
                cacheWrite: (entry["cache_creation_input_token_cost"] as? NSNumber)?.doubleValue ?? input
            )
        }
        return rates.isEmpty ? nil : PricingTable(rates: rates)
    }
}

enum PricingLoader {
    static func load() async -> PricingTable {
        if let fresh = readIfFresh(Config.t3RatesFile) { return fresh }
        if let cached = readIfFresh(Config.ratesCacheFile) { return cached }
        if let downloaded = await download() { return downloaded }
        // Stale is better than nothing.
        return read(Config.t3RatesFile) ?? read(Config.ratesCacheFile) ?? .empty
    }

    private static func readIfFresh(_ url: URL) -> PricingTable? {
        guard
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
            Date().timeIntervalSince(modified) < Config.ratesMaxAge
        else { return nil }
        return read(url)
    }

    private static func read(_ url: URL) -> PricingTable? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return PricingTable.parse(data)
    }

    private static func download() async -> PricingTable? {
        do {
            let (data, _) = try await URLSession.shared.data(from: Config.ratesDownloadURL)
            guard let table = PricingTable.parse(data) else { return nil }
            let dir = Config.ratesCacheFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: Config.ratesCacheFile, options: .atomic)
            return table
        } catch {
            NSLog("UsageBar: pricing download failed: \(error.localizedDescription)")
            return nil
        }
    }
}
