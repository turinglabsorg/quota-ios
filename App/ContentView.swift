import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if model.isPaired {
                    usageList
                } else {
                    PairingView()
                }
            }
            .navigationTitle("Quota")
            .toolbar {
                if model.isPaired {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("Settings"))
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(model)
            }
        }
    }

    private var usageList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
                if let payload = model.payload {
                    ForEach(payload.accounts) { account in
                        AccountCard(account: account, now: context.date, displayMode: model.displayMode)
                    }
                    if payload.accounts.isEmpty {
                        Text("No accounts are linked on the server. Run `quota-server link <service>` on your Mac.")
                            .foregroundStyle(.secondary)
                    }
                    Section {
                    } footer: {
                        Text(updatedText(payload, now: context.date))
                    }
                } else if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refresh() }
        }
        .task { await model.refresh() }
    }

    private func updatedText(_ payload: UsagePayload, now: Date) -> String {
        guard let refreshed = payload.refreshedAt else { return String(localized: "Waiting for data…") }
        return String(localized: "Updated \(Formatting.relative(refreshed, from: now))")
    }
}

struct AccountCard: View {
    let account: AccountUsage
    let now: Date
    let displayMode: DisplayMode

    var body: some View {
        Section {
            ForEach(Array(account.usageWindows.enumerated()), id: \.offset) { _, window in
                windowRow(window)
            }
            if let issue = account.issue {
                Label {
                    Text(LocalizedStringKey(issue.message))
                } icon: {
                    Image(systemName: issue.kind == "sessionExpired" ? "key.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if account.fetchedAt == nil {
                Text("Loading…").foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 8) {
                ProviderGlyph(provider: account.provider)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(account.provider.accent)
                Text(account.provider.displayName)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                    .textCase(nil)
                if let plan = account.plan {
                    Text(plan)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .textCase(nil)
                }
                Spacer()
            }
        } footer: {
            if let email = account.email {
                Text(verbatim: email)
            }
        }
    }

    private func windowRow(_ window: UsageWindow) -> some View {
        let remaining = window.remainingPercent(at: now)
        let value = displayMode.value(remaining: remaining)
        let level = UsageLevel(remainingPercent: remaining)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                Spacer()
                Text(verbatim: "\(value)%")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(level == .normal ? Color.primary : level.color)
                Text(displayMode.suffix)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            UsageBar(fraction: Double(value) / 100, color: level.color)
            if let resetsAt = window.resetsAt {
                Text(window.hasReset(at: now)
                    ? String(localized: "Reset, updating")
                    : String(localized: "Resets in \(Formatting.countdown(to: resetsAt, from: now))"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
