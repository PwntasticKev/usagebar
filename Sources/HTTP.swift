import Foundation

/// Minimal JSON GET helper. Returns a loosely typed dictionary so unknown/extra fields never break parsing.
enum HTTP {
    static func getJSON(
        _ url: URL,
        headers: [String: String],
        unauthorizedHint: String
    ) async -> Result<[String: Any], UsageError> {
        var request = URLRequest(url: url, timeoutInterval: Config.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("no HTTP response"))
            }
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: return .failure(.unauthorized(unauthorizedHint))
            default: return .failure(.http(http.statusCode))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.decode("body is not a JSON object"))
            }
            return .success(json)
        } catch let error as URLError {
            return .failure(.network(error.localizedDescription))
        } catch {
            return .failure(.decode(error.localizedDescription))
        }
    }
}

enum Shell {
    /// Runs a binary and returns trimmed stdout, or nil on non-zero exit.
    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            NSLog("UsageBar: failed to launch \(path): \(error)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DateParsing {
    private static let iso = ISO8601DateFormatter()

    /// Parses ISO-8601 strings, tolerating microsecond fractions like "2026-11-15T01:59:59.721313+00:00".
    static func iso8601(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return iso.date(from: trimmed)
    }

    static func unixSeconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}
