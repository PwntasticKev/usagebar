import Foundation

enum Format {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "1d 4h", "4h 12m", "12m", or "now".
    static func countdown(until date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let total = Int(date.timeIntervalSince(now))
        guard total > 60 else { return "now" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// 5.62B, 16.5M, 840K, 12
    static func tokens(_ value: Int) -> String {
        let v = Double(value)
        switch v {
        case 1e9...: return String(format: "%.2fB", v / 1e9)
        case 1e6...: return String(format: "%.1fM", v / 1e6)
        case 1e3...: return String(format: "%.0fK", v / 1e3)
        default: return "\(value)"
        }
    }

    private static let wholeDollars: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    /// $1,563 for large amounts, $2.38 below $100.
    static func cost(_ value: Double) -> String {
        if value >= 100 { return wholeDollars.string(from: NSNumber(value: value)) ?? "$\(Int(value))" }
        return String(format: "$%.2f", value)
    }

    private static let shortReset: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    static func resetLine(_ date: Date?) -> String {
        guard let date else { return "reset unknown" }
        return "resets \(shortReset.string(from: date))"
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f
    }()

    static func tooltip(name: String, snap: UsageSnapshot, now: Date, warning: String?) -> String {
        var lines = ["\(name) weekly: \(percent(snap.usedPercent)) used, \(percent(snap.leftPercent)) left"]
        if let resetsAt = snap.resetsAt {
            lines.append("Resets \(resetFormatter.string(from: resetsAt)) (in \(countdown(until: resetsAt, now: now)))")
        }
        if let pace = snap.elapsedFraction(now: now) {
            lines.append("Week elapsed: \(percent(pace * 100)) (white tick)")
        }
        if let detail = snap.detail { lines.append(detail) }
        lines.append("Source: \(snap.source)")
        if let warning { lines.append("⚠︎ Showing last value — \(warning)") }
        return lines.joined(separator: "\n")
    }
}
