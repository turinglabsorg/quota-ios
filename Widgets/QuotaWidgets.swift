import SwiftUI
import WidgetKit

@main
struct QuotaWidgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

struct UsageEntry: TimelineEntry {
    enum State {
        case ready(UsagePayload)
        case notPaired
        case unreachable
    }

    let date: Date
    let state: State
    let displayMode: DisplayMode
}

struct UsageProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), state: .ready(.sample), displayMode: .remaining)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(UsageEntry(date: Date(), state: cachedState(), displayMode: DisplayMode.current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let state: UsageEntry.State
            if QuotaClient.showsSampleData {
                state = .ready(.sample)
            } else if !QuotaClient.isPaired {
                state = .notPaired
            } else if let payload = try? await QuotaClient.fetchUsage() {
                state = .ready(payload)
            } else {
                state = cachedState()
            }
            // Same data, later dates: countdowns and passed resets stay current between fetches.
            let now = Date()
            let entries = stride(from: 0, to: Self.refreshInterval, by: 5 * 60).map { offset in
                UsageEntry(date: now.addingTimeInterval(offset), state: state, displayMode: DisplayMode.current)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refreshInterval))))
        }
    }

    private func cachedState() -> UsageEntry.State {
        if QuotaClient.showsSampleData { return .ready(.sample) }
        guard QuotaClient.isPaired else { return .notPaired }
        return QuotaClient.cachedUsage().map { .ready($0) } ?? .unreachable
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuotaUsage", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quota")
        .description("How much of your Claude, Codex, Grok and Ollama Cloud limits you have left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        switch entry.state {
        case .ready(let payload):
            content(payload)
        case .notPaired:
            message(String(localized: "Open Quota to pair"), symbol: "link")
        case .unreachable:
            message(String(localized: "Can't reach the Quota server."), symbol: "wifi.exclamationmark")
        }
    }

    @ViewBuilder
    private func content(_ payload: UsagePayload) -> some View {
        let rows = payload.accounts.compactMap { Row(account: $0, now: entry.date) }
        switch family {
        case .accessoryCircular:
            CircularView(row: rows.min { $0.remaining < $1.remaining }, mode: entry.displayMode)
        case .accessoryRectangular:
            RectangularView(rows: Array(rows.prefix(4)), mode: entry.displayMode)
        case .accessoryInline:
            Text(rows.map { "\($0.account.provider.shortName) \($0.values(entry.displayMode))" }.joined(separator: " · "))
        case .systemMedium:
            MediumView(rows: Array(rows.prefix(4)), payload: payload, now: entry.date, mode: entry.displayMode)
        default:
            SmallView(rows: Array(rows.prefix(4)), payload: payload, now: entry.date, mode: entry.displayMode)
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3)
            if family != .accessoryCircular {
                Text(text)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
    }
}

struct Bar: Identifiable {
    let id: Int
    let window: UsageWindow
    let remaining: Int

    var level: UsageLevel { UsageLevel(remainingPercent: remaining) }
}

struct Row: Identifiable {
    let account: AccountUsage
    /// Session above weekly (or monthly) when the account reports both, as in the Mac menu bar.
    let bars: [Bar]
    /// The account-wide window closest to its limit.
    let window: UsageWindow
    let remaining: Int

    init?(account: AccountUsage, now: Date) {
        guard let headline = account.headline(at: now) else { return nil }
        self.account = account
        window = headline.window
        remaining = headline.remaining
        bars = account.barWindows(at: now).enumerated().map { Bar(id: $0.offset, window: $0.element, remaining: $0.element.remainingPercent(at: now)) }
    }

    var id: UUID { account.id }
    var level: UsageLevel { UsageLevel(remainingPercent: remaining) }

    func values(_ mode: DisplayMode) -> String {
        bars.map { "\(mode.value(remaining: $0.remaining))%" }.joined(separator: "/")
    }
}

/// One bar with its value at the end, colored by its own level.
private struct BarLine: View {
    let bar: Bar
    let mode: DisplayMode
    let valueSize: CGFloat
    let valueWidth: CGFloat

    var body: some View {
        let value = mode.value(remaining: bar.remaining)
        HStack(spacing: 4) {
            UsageBar(fraction: Double(value) / 100, color: bar.level.color, height: 4)
            Text(verbatim: "\(value)%")
                .font(.system(size: valueSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(bar.level == .normal ? Color.primary : bar.level.color)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }
}

private struct SmallView: View {
    let rows: [Row]
    let payload: UsagePayload
    let now: Date
    let mode: DisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    ProviderGlyph(provider: row.account.provider)
                        .frame(width: 11, height: 11)
                        .foregroundStyle(row.account.provider.accent)
                    Text(row.account.provider.shortName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 40, alignment: .leading)
                    VStack(spacing: 2) {
                        ForEach(row.bars) { BarLine(bar: $0, mode: mode, valueSize: 10, valueWidth: 27) }
                    }
                }
            }
            Spacer(minLength: 0)
            UpdatedLabel(payload: payload, now: now)
        }
    }
}

private struct MediumView: View {
    let rows: [Row]
    let payload: UsagePayload
    let now: Date
    let mode: DisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { index in
                    GridRow(alignment: .top) {
                        tile(rows[index])
                        if index + 1 < rows.count {
                            tile(rows[index + 1])
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            UpdatedLabel(payload: payload, now: now)
        }
    }

    private func tile(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                ProviderGlyph(provider: row.account.provider)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(row.account.provider.accent)
                Text(row.account.provider.shortName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let resetsAt = row.window.resetsAt, !row.window.hasReset(at: now) {
                    Text("\(Image(systemName: "arrow.clockwise")) \(Formatting.countdown(to: resetsAt, from: now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ForEach(row.bars) { BarLine(bar: $0, mode: mode, valueSize: 12, valueWidth: 34) }
        }
    }
}

private struct UpdatedLabel: View {
    let payload: UsagePayload
    let now: Date

    var body: some View {
        if let refreshed = payload.refreshedAt {
            let stale = now.timeIntervalSince(refreshed) > 30 * 60
            Text("Updated \(Formatting.relative(refreshed, from: now))")
                .font(.system(size: 9))
                .foregroundStyle(stale ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
    }
}

private struct CircularView: View {
    let row: Row?
    let mode: DisplayMode

    var body: some View {
        if let row {
            Gauge(value: Double(row.remaining), in: 0...100) {
                ProviderGlyph(provider: row.account.provider)
            } currentValueLabel: {
                VStack(spacing: 0) {
                    ProviderGlyph(provider: row.account.provider)
                        .frame(width: 9, height: 9)
                    Text(verbatim: "\(mode.value(remaining: row.remaining))")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}

private struct RectangularView: View {
    let rows: [Row]
    let mode: DisplayMode

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { index in
                GridRow {
                    cell(rows[index])
                    if index + 1 < rows.count {
                        cell(rows[index + 1])
                    }
                }
            }
        }
    }

    private func cell(_ row: Row) -> some View {
        HStack(spacing: 3) {
            ProviderGlyph(provider: row.account.provider)
                .frame(width: 10, height: 10)
            Text(verbatim: row.values(mode))
                .font(.system(size: row.bars.count > 1 ? 12 : 15, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }
}
