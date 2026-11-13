import Foundation

/// Reads Claude Code's OAuth token from the login keychain (read-only) and queries the usage endpoint
/// that backs claude.ai > Settings > Usage.
enum ClaudeProvider {
    private static let reauthHint = "Run `claude` once to refresh."

    static func fetch() async -> Result<UsageSnapshot, UsageError> {
        let tokenResult = await Task.detached { readAccessToken() }.value
        guard case .success(let token) = tokenResult else {
            if case .failure(let error) = tokenResult { return .failure(error) }
            return .failure(.credentialsMissing(reauthHint))
        }
        let response = await HTTP.getJSON(
            Config.claudeUsageURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": Config.claudeOAuthBeta,
            ],
            unauthorizedHint: reauthHint
        )
        return response.flatMap(parse)
    }

    private static func readAccessToken() -> Result<String, UsageError> {
        guard let raw = Shell.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", Config.claudeKeychainService, "-w"]
        ) else {
            return .failure(.credentialsMissing("Sign in with `claude` first."))
        }
        guard
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            return .failure(.decode("keychain entry has no accessToken"))
        }
        return .success(token)
    }

    static func parse(_ json: [String: Any]) -> Result<UsageSnapshot, UsageError> {
        let limits = json["limits"] as? [[String: Any]] ?? []
        let weekly = limits.first { ($0["kind"] as? String) == "weekly_all" }
        let scopedDetail = limits
            .filter { ($0["kind"] as? String) == "weekly_scoped" }
            .compactMap(describeScoped)
            .joined(separator: ", ")

        if let weekly, let percent = (weekly["percent"] as? NSNumber)?.doubleValue {
            return .success(UsageSnapshot(
                usedPercent: percent,
                resetsAt: DateParsing.iso8601(weekly["resets_at"]),
                windowSeconds: Config.weekSeconds,
                detail: scopedDetail.isEmpty ? nil : scopedDetail,
                source: "claude.ai"
            ))
        }

        // Fallback to the older shape.
        if let sevenDay = json["seven_day"] as? [String: Any],
           let util = (sevenDay["utilization"] as? NSNumber)?.doubleValue {
            return .success(UsageSnapshot(
                usedPercent: util,
                resetsAt: DateParsing.iso8601(sevenDay["resets_at"]),
                windowSeconds: Config.weekSeconds,
                detail: nil,
                source: "claude.ai"
            ))
        }
        return .failure(.decode("no weekly limit in Claude response"))
    }

    private static func describeScoped(_ limit: [String: Any]) -> String? {
        guard let percent = (limit["percent"] as? NSNumber)?.intValue else { return nil }
        let scope = limit["scope"] as? [String: Any]
        let model = scope?["model"] as? [String: Any]
        let name = model?["display_name"] as? String ?? "Scoped"
        return "\(name) \(percent)%"
    }
}
