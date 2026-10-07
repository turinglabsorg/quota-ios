import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var server = QuotaClient.serverURL?.absoluteString ?? ""
    @State private var code = ""
    @State private var isPairing = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Quota shows the usage that quota-server reads on your Mac. On that Mac, run `quota-server pair` and enter the code here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Server") {
                TextField(text: $server, prompt: Text(verbatim: "https://quota.example.com")) {
                    Text("Server")
                }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Pairing code") {
                TextField(text: $code, prompt: Text(verbatim: "1234 5678")) {
                    Text("Pairing code")
                }
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(8))
                    if digits != value { code = digits }
                }
            }
            Section {
                Button {
                    Task {
                        isPairing = true
                        error = await model.pair(server: server, code: code)
                        isPairing = false
                    }
                } label: {
                    HStack {
                        Text("Pair")
                        if isPairing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPairing || code.filter(\.isNumber).count != 8)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }
}
