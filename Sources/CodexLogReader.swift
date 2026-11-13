import Foundation

/// Offline fallback: scans the newest Codex session log for its latest `rate_limits` payload.
/// Layout: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
enum CodexLogReader {
    static func latestSnapshot() -> UsageSnapshot? {
        guard let file = newestLogFile(), let tail = readTail(of: file) else { return nil }
        let lines = tail.split(separator: "\n").reversed()
        for line in lines where line.contains("\"rate_limits\"") {
            if let snapshot = parseLine(String(line)) { return snapshot }
        }
        return nil
    }

    private static func newestLogFile() -> URL? {
        let fm = FileManager.default
        var dir = Config.codexSessionsDir
        // Walk year → month → day, always taking the lexically newest folder.
        for _ in 0..<3 {
            guard let next = sortedChildren(of: dir, fm).filter(\.hasDirectoryPath).last else { return nil }
            dir = next
        }
        return sortedChildren(of: dir, fm)
            .filter { $0.pathExtension == "jsonl" }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private static func sortedChildren(of dir: URL, _ fm: FileManager) -> [URL] {
        let items = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func readTail(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(Config.codexLogTailBytes) ? size - UInt64(Config.codexLogTailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func parseLine(_ line: String) -> UsageSnapshot? {
        guard
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let limits = findRateLimits(in: json)
        else { return nil }
        let windows = ["primary", "secondary"].compactMap { limits[$0] as? [String: Any] }
        guard let weekly = CodexProvider.pickWeekly(windows, secondsKey: "window_minutes", scale: 60) else {
            return nil
        }
        let minutes = (weekly["window_minutes"] as? NSNumber)?.doubleValue ?? Config.weekSeconds / 60
        return UsageSnapshot(
            usedPercent: (weekly["used_percent"] as? NSNumber)?.doubleValue ?? 0,
            resetsAt: DateParsing.unixSeconds(weekly["resets_at"]),
            windowSeconds: minutes * 60,
            detail: "From last Codex session (offline)",
            source: "codex log"
        )
    }

    private static func findRateLimits(in value: Any) -> [String: Any]? {
        guard let dict = value as? [String: Any] else { return nil }
        if let limits = dict["rate_limits"] as? [String: Any] { return limits }
        for child in dict.values {
            if let found = findRateLimits(in: child) { return found }
        }
        return nil
    }
}
