import AppKit
import Combine

/// Polls both providers on a timer and after wake-from-sleep. Publishes immutable state values.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var claude: ProviderState = .loading
    @Published private(set) var codex: ProviderState = .loading
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var inFlight = false

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Config.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        Task { @MainActor in
            async let claudeResult = ClaudeProvider.fetch()
            async let codexResult = CodexProvider.fetch()
            let (c, x) = await (claudeResult, codexResult)
            log("Claude", c)
            log("Codex", x)
            claude = claude.applying(c)
            codex = codex.applying(x)
            lastUpdated = Date()
            inFlight = false
        }
    }

    private func log(_ name: String, _ result: Result<UsageSnapshot, UsageError>) {
        if case .failure(let error) = result {
            NSLog("UsageBar: \(name) fetch failed: \(error.localizedDescription)")
        }
    }
}
