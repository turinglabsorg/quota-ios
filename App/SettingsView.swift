import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Show", selection: $model.displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                Section("Server") {
                    Text(verbatim: QuotaClient.serverURL?.absoluteString ?? "-")
                        .foregroundStyle(.secondary)
                    Button("Unpair this device", role: .destructive) {
                        model.unpair()
                        dismiss()
                    }
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
