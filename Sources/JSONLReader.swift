import Foundation

/// Fast incremental reader for append-only JSONL files.
enum JSONLReader {
    /// Calls `handler` for each complete line after `offset`.
    /// Returns the offset just past the last complete line (a trailing partial line is left for next time).
    static func readLines(
        at url: URL,
        from offset: UInt64,
        handler: (UnsafeRawBufferPointer) -> Void
    ) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return offset
        }

        var consumed = offset
        var carry = Data()
        while let chunk = try? handle.read(upToCount: Config.scanChunkSize), !chunk.isEmpty {
            let buffer = carry.isEmpty ? chunk : carry + chunk
            let used = buffer.withUnsafeBytes { splitLines($0, handler) }
            consumed += UInt64(used)
            carry = buffer.subdata(in: (buffer.startIndex + used)..<buffer.endIndex)
        }
        return consumed
    }

    private static func splitLines(_ raw: UnsafeRawBufferPointer, _ handler: (UnsafeRawBufferPointer) -> Void) -> Int {
        guard let base = raw.baseAddress else { return 0 }
        var start = 0
        while start < raw.count, let newline = memchr(base + start, 0x0A, raw.count - start) {
            let end = base.distance(to: UnsafeRawPointer(newline))
            if end > start {
                handler(UnsafeRawBufferPointer(start: base + start, count: end - start))
            }
            start = end + 1
        }
        return start
    }

    static func contains(_ line: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let base = line.baseAddress else { return false }
        return needle.withUnsafeBytes { n in
            memmem(base, line.count, n.baseAddress, n.count) != nil
        }
    }

    static func object(_ line: UnsafeRawBufferPointer) -> [String: Any]? {
        let data = Data(bytes: line.baseAddress!, count: line.count)
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

enum LogTimestamp {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func day(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        guard let date = withFraction.date(from: text) ?? plain.date(from: text) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }
}
