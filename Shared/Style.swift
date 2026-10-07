import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case remaining
    case used

    static let key = "displayMode"

    static var current: DisplayMode {
        DisplayMode(rawValue: QuotaClient.defaults.string(forKey: key) ?? "") ?? .remaining
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: String(localized: "Percentage left")
        case .used: String(localized: "Percentage used")
        }
    }

    var suffix: String {
        switch self {
        case .remaining: String(localized: "left")
        case .used: String(localized: "used")
        }
    }

    func value(remaining: Int) -> Int {
        self == .remaining ? remaining : 100 - remaining
    }
}

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * fraction) : 0)
            }
        }
        .frame(height: height)
    }
}

extension AccountUsage {
    /// The account-wide window the menu bar would show, with its remaining percent at `now`.
    func headline(at now: Date) -> (window: UsageWindow, remaining: Int)? {
        let snapshot = ProviderSnapshot(provider: provider, plan: plan, account: email, windows: usageWindows, fetchedAt: fetchedAt ?? now)
        guard let window = snapshot.tightestWindow(at: now) else { return nil }
        return (window, window.remainingPercent(at: now))
    }
}

extension UsagePayload {
    static let sample: UsagePayload = {
        let now = Date()
        func account(_ provider: Provider, plan: String?, _ windows: [UsageWindow]) -> AccountUsage {
            let account = Account(provider: provider, source: .cli, email: "name@example.com", plan: plan)
            let snapshot = ProviderSnapshot(provider: provider, plan: plan, account: account.email, windows: windows, fetchedAt: now)
            return AccountUsage(account: account, snapshot: snapshot, issue: nil)
        }
        return UsagePayload(generatedAt: now, refreshedAt: now, accounts: [
            account(.claude, plan: "Team", [
                UsageWindow(kind: .session, usedPercent: 28, resetsAt: now.addingTimeInterval(2 * 3_600 + 600)),
                UsageWindow(kind: .weekly, usedPercent: 64, resetsAt: now.addingTimeInterval(3 * 86_400)),
            ]),
            account(.codex, plan: "Plus", [UsageWindow(kind: .weekly, usedPercent: 37, resetsAt: now.addingTimeInterval(5 * 86_400))]),
            account(.grok, plan: nil, [UsageWindow(kind: .weekly, usedPercent: 96, resetsAt: now.addingTimeInterval(9 * 3_600))]),
            account(.ollama, plan: "Max", [UsageWindow(kind: .monthly, usedPercent: 53, resetsAt: now.addingTimeInterval(13 * 86_400))]),
        ])
    }()
}

extension Provider {
    /// Fits the narrow widget rows ("Ollama Cloud" does not).
    var shortName: String {
        self == .ollama ? "Ollama" : displayName
    }
}
