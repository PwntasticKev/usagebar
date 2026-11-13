import Foundation

/// Claude Code transcript line: `{"type":"assistant","timestamp":..,"requestId":..,"message":{"id","model","usage":{..}}}`
enum ClaudeLineParser {
    static let needle = Array(#""usage""#.utf8)

    struct Entry {
        let dedupeKey: String?
        let model: String
        let day: Date
        let counts: TokenCounts
    }

    static func parse(_ line: UnsafeRawBufferPointer) -> Entry? {
        guard
            JSONLReader.contains(line, needle),
            let json = JSONLReader.object(line),
            (json["type"] as? String) == "assistant",
            let message = json["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any],
            let model = message["model"] as? String,
            !model.hasPrefix("<"),  // "<synthetic>" placeholder messages
            let day = LogTimestamp.day(json["timestamp"])
        else { return nil }

        let counts = TokenCounts(
            input: int(usage["input_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]),
            cacheWrite: int(usage["cache_creation_input_tokens"]),
            output: int(usage["output_tokens"])
        )
        let dedupe = (message["id"] as? String).map { "\($0):\(json["requestId"] as? String ?? "")" }
        return Entry(dedupeKey: dedupe, model: model, day: day, counts: counts)
    }
}

/// Codex rollout lines: `turn_context` carries the model; `token_count` events carry per-turn usage.
enum CodexLineParser {
    static let contextNeedle = Array(#""turn_context""#.utf8)
    static let tokenNeedle = Array(#""token_count""#.utf8)

    enum Event {
        case model(String)
        case tokens(runningTotal: Int, day: Date, counts: TokenCounts)
    }

    static func parse(_ line: UnsafeRawBufferPointer) -> Event? {
        let isContext = JSONLReader.contains(line, contextNeedle)
        guard isContext || JSONLReader.contains(line, tokenNeedle),
              let json = JSONLReader.object(line),
              let payload = json["payload"] as? [String: Any]
        else { return nil }

        if isContext, (json["type"] as? String) == "turn_context" {
            return (payload["model"] as? String).map(Event.model)
        }
        guard
            (payload["type"] as? String) == "token_count",
            let info = payload["info"] as? [String: Any],
            let last = info["last_token_usage"] as? [String: Any],
            let day = LogTimestamp.day(json["timestamp"])
        else { return nil }

        let total = (info["total_token_usage"] as? [String: Any]).map { int($0["total_tokens"]) } ?? -1
        let input = int(last["input_tokens"])
        let cached = int(last["cached_input_tokens"])
        let counts = TokenCounts(
            input: max(0, input - cached),  // Codex input includes cached tokens
            cacheRead: cached,
            cacheWrite: int(last["cache_write_input_tokens"]),
            output: int(last["output_tokens"])
        )
        return .tokens(runningTotal: total, day: day, counts: counts)
    }
}

private func int(_ value: Any?) -> Int {
    (value as? NSNumber)?.intValue ?? 0
}
