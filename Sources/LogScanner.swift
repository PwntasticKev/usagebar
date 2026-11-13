import Foundation

/// Incrementally scans Claude Code and Codex session logs. Each file is read once; later scans only
/// read bytes appended since the previous pass. State is confined to this actor.
actor LogScanner {
    private struct FileState {
        let provider: Provider
        let sessionKey: String
        var offset: UInt64 = 0
        var buckets: [BucketKey: TokenCounts] = [:]
        var codexModel: String?
        var codexLastTotal = -1

        mutating func add(_ counts: TokenCounts, model: String, day: Date) {
            let key = BucketKey(model: model, day: day)
            buckets[key] = (buckets[key] ?? .zero).adding(counts)
        }
    }

    private struct Candidate {
        let url: URL
        let provider: Provider
        let size: UInt64
    }

    private var files: [String: FileState] = [:]
    private var seenClaudeMessages = Set<String>()

    func scan(modifiedSince cutoff: Date) -> [ScannedFile] {
        let candidates = listFiles(Config.claudeProjectsDir, .claude, cutoff)
            + listFiles(Config.codexSessionsDir, .codex, cutoff)
        if candidates.contains(where: { (files[$0.url.path]?.offset ?? 0) > $0.size }) {
            // A log was truncated/rewritten; rebuild from scratch so dedupe stays correct.
            files = [:]
            seenClaudeMessages = []
        }
        var live = Set<String>()
        for candidate in candidates {
            live.insert(candidate.url.path)
            scanFile(candidate)
        }
        files = files.filter { live.contains($0.key) }
        return files.values.map {
            ScannedFile(provider: $0.provider, sessionKey: $0.sessionKey, buckets: $0.buckets)
        }
    }

    private func scanFile(_ candidate: Candidate) {
        let path = candidate.url.path
        var state = files[path] ?? FileState(provider: candidate.provider, sessionKey: Self.sessionKey(candidate))
        guard candidate.size > state.offset else { return }

        state.offset = JSONLReader.readLines(at: candidate.url, from: state.offset) { line in
            switch candidate.provider {
            case .claude: handleClaude(line, &state)
            case .codex: handleCodex(line, &state)
            }
        }
        files[path] = state
    }

    private func handleClaude(_ line: UnsafeRawBufferPointer, _ state: inout FileState) {
        guard let entry = ClaudeLineParser.parse(line) else { return }
        if let key = entry.dedupeKey {
            guard seenClaudeMessages.insert(key).inserted else { return }
        }
        state.add(entry.counts, model: entry.model, day: entry.day)
    }

    private func handleCodex(_ line: UnsafeRawBufferPointer, _ state: inout FileState) {
        switch CodexLineParser.parse(line) {
        case .model(let model):
            state.codexModel = model
        case .tokens(let total, let day, let counts):
            // Codex re-emits token_count with unchanged totals (e.g. rate-limit refreshes); skip those.
            if total >= 0 {
                guard total != state.codexLastTotal else { return }
                state.codexLastTotal = total
            }
            state.add(counts, model: state.codexModel ?? "codex", day: day)
        case nil:
            return
        }
    }

    /// Subagent transcripts (…/<session>/subagents/*.jsonl) count toward their parent session.
    private static func sessionKey(_ candidate: Candidate) -> String {
        let components = candidate.url.pathComponents
        if let index = components.lastIndex(of: "subagents"), index > 0 {
            return components[index - 1]
        }
        return candidate.url.deletingPathExtension().lastPathComponent
    }

    private func listFiles(_ root: URL, _ provider: Provider, _ cutoff: Date) -> [Candidate] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [Candidate] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                let modified = values.contentModificationDate, modified >= cutoff,
                let size = values.fileSize
            else { continue }
            result.append(Candidate(url: url, provider: provider, size: UInt64(size)))
        }
        return result
    }
}
