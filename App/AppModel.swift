import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var payload: UsagePayload?
    @Published private(set) var isPaired = QuotaClient.isPaired
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var displayMode = DisplayMode.current {
        didSet {
            QuotaClient.defaults.set(displayMode.rawValue, forKey: DisplayMode.key)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static let isSampleMode = ProcessInfo.processInfo.arguments.contains("-QuotaSampleData")

    init() {
        QuotaClient.showsSampleData = Self.isSampleMode
        if Self.isSampleMode {
            payload = .sample
            isPaired = true
        } else {
            payload = QuotaClient.cachedUsage()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() async {
        guard isPaired, !isLoading, !Self.isSampleMode else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            payload = try await QuotaClient.fetchUsage()
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch QuotaClient.Failure.unauthorized {
            unpair()
            errorMessage = QuotaClient.Failure.unauthorized.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pair(server: String, code: String) async -> String? {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://\(text)" }
        guard let url = URL(string: text), url.host != nil else {
            return String(localized: "Enter the address of your Quota server.")
        }
        do {
            try await QuotaClient.pair(server: url, code: code, deviceName: UIDevice.current.name)
            isPaired = true
            errorMessage = nil
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func unpair() {
        QuotaClient.unpair()
        isPaired = false
        payload = nil
        WidgetCenter.shared.reloadAllTimelines()
    }
}
