import Charts
import SwiftUI

/// Expanded hover panel: 7-day tokens, cost, sessions, daily chart, top models, limit resets.
struct DetailView: View {
    let stats: UsageStats?
    let isScanning: Bool
    let limits: [(Provider, ProviderState)]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let stats {
                header(stats)
                DailyChart(days: stats.days).frame(height: Layout.chartHeight)
                section {
                    ForEach(stats.providers) { ProviderLine(totals: $0) }
                }
                section(title: "Top models") {
                    ForEach(stats.models.prefix(Config.topModelCount)) { ModelLine(totals: $0) }
                }
            } else {
                Text(isScanning ? "Reading session logs…" : "No local usage found")
                    .font(.system(size: Layout.detailFontSize))
                    .foregroundStyle(.secondary)
            }
            section(title: "Weekly limits") {
                ForEach(limits, id: \.0) { LimitLine(provider: $0.0, state: $0.1, now: now) }
            }
        }
        .frame(width: Layout.detailWidth, alignment: .leading)
    }

    private func header(_ stats: UsageStats) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("LAST \(stats.rangeDays) DAYS")
                    .font(.system(size: Layout.detailSmallFontSize, weight: .semibold))
                    .foregroundStyle(Palette.resetText)
                Spacer()
                if isScanning { ProgressView().controlSize(.mini).scaleEffect(0.6) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Format.tokens(stats.totalTokens))
                    .font(.system(size: Layout.headlineFontSize, weight: .semibold).monospacedDigit())
                Text("tokens").font(.system(size: Layout.detailSmallFontSize)).foregroundStyle(.secondary)
                Spacer()
                Text(Format.cost(stats.totalCost))
                    .font(.system(size: Layout.headlineFontSize - 3, weight: .semibold).monospacedDigit())
            }
            Text("\(stats.totalSessions) sessions · \(Format.tokens(stats.totals.cacheRead)) cached")
                .font(.system(size: Layout.detailSmallFontSize))
                .foregroundStyle(Palette.resetText)
        }
        .foregroundStyle(.white)
    }

    private func section<Content: View>(title: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider().overlay(Color.white.opacity(0.08))
            if let title {
                Text(title.uppercased())
                    .font(.system(size: Layout.detailSmallFontSize - 0.5, weight: .semibold))
                    .foregroundStyle(Palette.resetText)
                    .padding(.top, 2)
            }
            content()
        }
    }
}

private struct DailyChart: View {
    let days: [DayTotals]

    var body: some View {
        Chart(days) { day in
            AreaMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Tokens", day.tokens),
                stacking: .unstacked
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(by: .value("Provider", day.provider.name))
            .opacity(0.18)

            LineMark(x: .value("Day", day.day, unit: .day), y: .value("Tokens", day.tokens))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.3))
                .foregroundStyle(by: .value("Provider", day.provider.name))
        }
        .chartForegroundStyleScale([Provider.claude.name: Palette.claude, Provider.codex.name: Palette.codex])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let tokens = value.as(Int.self) { Text(Format.tokens(tokens)) }
                }
                .font(.system(size: 7))
                .foregroundStyle(Palette.resetText)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: false)
                    .font(.system(size: 7))
                    .foregroundStyle(Palette.resetText)
            }
        }
    }
}

private struct ProviderLine: View {
    let totals: ProviderTotals

    var body: some View {
        DetailRow(
            provider: totals.provider,
            label: totals.provider.name,
            note: "\(totals.sessions) sess",
            tokens: totals.tokens,
            cost: totals.cost,
            emphasized: true
        )
    }
}

private struct ModelLine: View {
    let totals: ModelTotals

    var body: some View {
        DetailRow(
            provider: totals.provider,
            label: totals.model,
            note: nil,
            tokens: totals.tokens,
            cost: totals.cost,
            emphasized: false
        )
    }
}

private struct DetailRow: View {
    let provider: Provider
    let label: String
    let note: String?
    let tokens: Int
    let cost: Double
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: provider, size: Layout.iconSize - 1)
            Text(label)
                .font(.system(size: Layout.detailFontSize, weight: emphasized ? .medium : .regular))
                .foregroundStyle(.white.opacity(emphasized ? 1 : 0.8))
                .lineLimit(1)
                .truncationMode(.middle)
            if let note {
                Text(note).font(.system(size: Layout.detailSmallFontSize)).foregroundStyle(Palette.resetText)
            }
            Spacer(minLength: 4)
            Text(Format.tokens(tokens))
                .font(.system(size: Layout.detailFontSize).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, alignment: .trailing)
            Text(Format.cost(cost))
                .font(.system(size: Layout.detailFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct LimitLine: View {
    let provider: Provider
    let state: ProviderState
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: provider, size: Layout.iconSize - 1)
            Text(primary)
                .font(.system(size: Layout.detailFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Text(secondary)
                .font(.system(size: Layout.detailSmallFontSize).monospacedDigit())
                .foregroundStyle(Palette.resetText)
                .lineLimit(1)
        }
    }

    private var primary: String {
        switch state {
        case .loading: return "…"
        case .failed: return "unavailable"
        case .ready(let s), .stale(let s, _): return "\(Format.percent(s.usedPercent)) used"
        }
    }

    private var secondary: String {
        switch state {
        case .loading: return ""
        case .failed(let message): return message
        case .ready(let s): return Format.resetLine(s.resetsAt)
        case .stale(let s, _): return "⚠︎ " + Format.resetLine(s.resetsAt)
        }
    }
}
