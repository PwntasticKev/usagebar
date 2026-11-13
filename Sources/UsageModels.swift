import Foundation

/// One rate-limit window as reported by a provider. Immutable value type.
struct UsageSnapshot: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
    let windowSeconds: TimeInterval
    let detail: String?
    let source: String

    var leftPercent: Double { max(0, 100 - usedPercent) }

    /// Fraction of the window already elapsed (0...1); nil when the reset time is unknown.
    func elapsedFraction(now: Date) -> Double? {
        guard let resetsAt, windowSeconds > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1 - remaining / windowSeconds))
    }
}

enum ProviderState: Equatable {
    case loading
    case ready(UsageSnapshot)
    case stale(UsageSnapshot, reason: String)
    case failed(String)

    var snapshot: UsageSnapshot? {
        switch self {
        case .ready(let s), .stale(let s, _): return s
        case .loading, .failed: return nil
        }
    }

    /// Returns the next state for a fetch result, keeping the last good value on transient failure.
    func applying(_ result: Result<UsageSnapshot, UsageError>) -> ProviderState {
        switch result {
        case .success(let snap):
            return .ready(snap)
        case .failure(let error):
            let reason = error.localizedDescription
            if let previous = snapshot { return .stale(previous, reason: reason) }
            return .failed(reason)
        }
    }
}

enum UsageError: LocalizedError, Equatable {
    case credentialsMissing(String)
    case unauthorized(String)
    case http(Int)
    case decode(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .credentialsMissing(let hint): return "No login found. \(hint)"
        case .unauthorized(let hint): return "Login expired. \(hint)"
        case .http(let code): return "Server returned HTTP \(code)"
        case .decode(let what): return "Unexpected response: \(what)"
        case .network(let msg): return "Network error: \(msg)"
        }
    }
}
