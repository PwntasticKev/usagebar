import SwiftUI

/// Whether the hover detail panel is showing.
@MainActor
final class PanelState: ObservableObject {
    @Published var expanded = false
}

/// Root content: compact rows always at the bottom; detail grows above them on hover.
struct RootView: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var stats: StatsStore
    @ObservedObject var panel: PanelState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                if panel.expanded {
                    DetailView(
                        stats: stats.stats,
                        isScanning: stats.isScanning,
                        limits: [(.claude, usage.claude), (.codex, usage.codex)],
                        now: context.date
                    )
                    .transition(.identity)
                }
                VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                    UsageRow(provider: .claude, state: usage.claude, now: context.date)
                    UsageRow(provider: .codex, state: usage.codex, now: context.date)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .fill(panel.expanded ? Palette.expandedBackground : Palette.background)
            )
            // Card only grows; the clip reveals the detail as its edge moves up.
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .environment(\.colorScheme, .dark)
        }
    }
}

/// Compact row. Bars read like a battery: fill = allowance LEFT this week.
struct UsageRow: View {
    let provider: Provider
    let state: ProviderState
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: provider)
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            values(left: nil, pace: nil, reset: "", stale: false)
        case .failed:
            values(left: nil, pace: nil, reset: "", stale: true)
        case .ready(let snap):
            values(left: snap.leftPercent, pace: expectedLeft(snap), reset: resetText(snap), stale: false)
        case .stale(let snap, _):
            values(left: snap.leftPercent, pace: expectedLeft(snap), reset: resetText(snap), stale: true)
        }
    }

    private func values(left: Double?, pace: Double?, reset: String, stale: Bool) -> some View {
        let isLow = (left ?? 100) <= Palette.dangerLeftPercent
        return HStack(spacing: 5) {
            UsageBar(fraction: (left ?? 0) / 100, pace: pace, color: isLow ? Palette.danger : provider.tint)
                .frame(width: Layout.barWidth)
            Text(left.map(Format.percent) ?? (stale ? "!" : "…"))
                .font(.system(size: Layout.percentFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(stale ? Color.yellow : Color.white)
                .frame(width: Layout.percentWidth, alignment: .trailing)
            Text(reset)
                .font(.system(size: Layout.resetFontSize).monospacedDigit())
                .foregroundStyle(Palette.resetText)
                .frame(width: Layout.resetWidth, alignment: .leading)
        }
    }

    /// Where the "left" fill would be if usage were spread evenly across the week.
    private func expectedLeft(_ snap: UsageSnapshot) -> Double? {
        snap.elapsedFraction(now: now).map { 1 - $0 }
    }

    private func resetText(_ snap: UsageSnapshot) -> String {
        Format.countdown(until: snap.resetsAt, now: now).replacingOccurrences(of: " ", with: "")
    }
}

/// Horizontal meter with an optional tick marking the even-pace point.
struct UsageBar: View {
    let fraction: Double
    let pace: Double?
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * width)
                if let pace {
                    Rectangle()
                        .fill(Palette.paceTick)
                        .frame(width: 1, height: Layout.barHeight + 2)
                        .offset(x: pace * width - 0.5)
                }
            }
            .frame(height: Layout.barHeight + 2)
        }
        .frame(height: Layout.barHeight + 2)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}
