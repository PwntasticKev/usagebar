import Foundation
import SwiftUI

/// Central constants. No magic numbers elsewhere.
enum Config {
    static let refreshInterval: TimeInterval = 60
    static let requestTimeout: TimeInterval = 15
    static let weekSeconds: TimeInterval = 7 * 24 * 60 * 60

    static let claudeKeychainService = "Claude Code-credentials"
    static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let claudeOAuthBeta = "oauth-2025-04-20"
    static let claudeWebUsageURL = URL(string: "https://claude.ai/settings/usage")!

    static let codexHome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    static let codexAuthFile = codexHome.appendingPathComponent("auth.json")
    static let codexSessionsDir = codexHome.appendingPathComponent("sessions")
    static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let codexWebUsageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!
    static let codexLogTailBytes = 512 * 1024

    static let userAgent = "UsageBar/1.0"

    // Local token/cost stats (parsed from session logs).
    static let claudeProjectsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    static let statsRangeDays = 7
    static let statsRefreshInterval: TimeInterval = 300
    static let statsStaleAfter: TimeInterval = 60
    static let scanChunkSize = 16 * 1024 * 1024
    static let topModelCount = 4

    // Model pricing: T3 Code's cached LiteLLM table first, then our own cached download.
    static let t3RatesFile = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".t3/userdata/usage-model-rates.json")
    static let ratesCacheFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UsageBar/model-rates.json")
    static let ratesDownloadURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!
    static let ratesMaxAge: TimeInterval = 7 * 24 * 60 * 60

    static let collapseDelay: TimeInterval = 0.3
}

enum Layout {
    static let cornerRadius: CGFloat = 8
    static let screenMargin: CGFloat = 8
    static let barWidth: CGFloat = 60
    static let barHeight: CGFloat = 4
    static let iconSize: CGFloat = 9
    static let percentWidth: CGFloat = 26
    static let resetWidth: CGFloat = 30
    static let percentFontSize: CGFloat = 9.5
    static let resetFontSize: CGFloat = 8
    static let rowSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6
    static let detailWidth: CGFloat = 250
    static let chartHeight: CGFloat = 54
    static let detailFontSize: CGFloat = 9.5
    static let detailSmallFontSize: CGFloat = 8.5
    static let headlineFontSize: CGFloat = 17
    /// Upper bound for the expanded card; the window briefly takes this size while animating.
    static let expandedCanvas = CGSize(width: 300, height: 560)
}

enum Motion {
    static let expand = Animation.smooth(duration: 0.32)
    static let collapse = Animation.smooth(duration: 0.22)
}

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.36, green: 0.78, blue: 0.62)
    static let danger = Color(red: 0.94, green: 0.33, blue: 0.31)
    static let track = Color.white.opacity(0.12)
    static let paceTick = Color.white.opacity(0.6)
    static let resetText = Color.white.opacity(0.35)
    static let background = Color(red: 0.07, green: 0.09, blue: 0.12).opacity(0.94)
    /// Fully solid while expanded so the detail text is easy to read over busy windows.
    static let expandedBackground = Color(red: 0.07, green: 0.09, blue: 0.12)
    /// Bar turns red when this much (or less) of the week's allowance is left.
    static let dangerLeftPercent: Double = 10
}
