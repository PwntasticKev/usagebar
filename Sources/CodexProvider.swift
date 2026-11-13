import Foundation

/// Reads the Codex CLI login (~/.codex/auth.json, read-only) and queries the ChatGPT usage endpoint.
/// Falls back to the most recent `rate_limits` event in Codex session logs when offline.
enum CodexProvider {
    private static let reauthHint = "Open Codex once to refresh."

    static func fetch() async -> Result<UsageSnapshot, UsageError> {
        let live = await fetchLive()
        if case .success = live { return live }
        let fallback = await Task.detached { CodexLogReader.latestSnapshot() }.value
        return fallback.map { .success($0) } ?? live
    }

    private static func fetchLive() async -> Result<UsageSnapshot, UsageError> {
        guard
            let data = try? Data(contentsOf: Config.codexAuthFile),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            !accessToken.isEmpty
        else {
            return .failure(.credentialsMissing("Sign in to Codex first."))
        }
        var headers = ["Authorization": "Bearer \(accessToken)"]
        if let accountId = tokens["account_id"] as? String {
            headers["ChatGPT-Account-Id"] = accountId
        }
        let response = await HTTP.getJSON(Config.codexUsageURL, headers: headers, unauthorizedHint: reauthHint)
        return response.flatMap(parse)
    }

    static func parse(_ json: [String: Any]) -> Result<UsageSnapshot, UsageError> {
        guard let rateLimit = json["rate_limit"] as? [String: Any] else {
            return .failure(.decode("no rate_limit in Codex response"))
        }
        let windows = ["primary_window", "secondary_window"].compactMap { rateLimit[$0] as? [String: Any] }
        guard let weekly = pickWeekly(windows, secondsKey: "limit_window_seconds") else {
            return .failure(.decode("no usage window in Codex response"))
        }
        let used = (weekly["used_percent"] as? NSNumber)?.doubleValue ?? 0
        let window = (weekly["limit_window_seconds"] as? NSNumber)?.doubleValue ?? Config.weekSeconds
        let plan = (json["plan_type"] as? String).map { "Plan: \($0)" }
        return .success(UsageSnapshot(
            usedPercent: used,
            resetsAt: DateParsing.unixSeconds(weekly["reset_at"]),
            windowSeconds: window,
            detail: plan,
            source: "chatgpt.com"
        ))
    }

    /// Picks the window closest to one week (Codex may also report a shorter 5h window).
    static func pickWeekly(_ windows: [[String: Any]], secondsKey: String, scale: Double = 1) -> [String: Any]? {
        windows.min { lhs, rhs in
            distanceFromWeek(lhs, secondsKey, scale) < distanceFromWeek(rhs, secondsKey, scale)
        }
    }

    private static func distanceFromWeek(_ window: [String: Any], _ key: String, _ scale: Double) -> Double {
        let seconds = ((window[key] as? NSNumber)?.doubleValue ?? 0) * scale
        return abs(seconds - Config.weekSeconds)
    }
}
