//
//  WiFiCredentialsFormView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import Security

// MARK: - Keychain helper


// MARK: - SwiftUI form
struct WiFiCredentialsFormView: View {
    @Environment(\.modelContext) var modelContext

    @State private var ssid: String = ""
    @State private var password: String = ""
    @State private var status: String?

    let onSave: (_ wifi: MinerWifiConnection) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Wi‑Fi Network")) {
                    TextField("SSID", text: $ssid)
                        .textContentType(.username)       // makes AutoFill nicer
#if os(iOS) || os(tvOS) || os(visionOS)
                        .autocapitalization(.none)
#endif
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                HStack {
                    Button("Cancel", action: onCancel)
                    Button("Save to Keychain") {
                        save()
                    }
                    .disabled(ssid.isEmpty || password.isEmpty)

                    if let status {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(EdgeInsets(top: 12, leading: 24, bottom: 24, trailing: 24))
            .navigationTitle("Save Wi‑Fi")
        }
        .onAppear(perform: loadIfExists)
    }

    // MARK: actions
    private func save() {
        do {
            try KeychainHelper.save(password, account: ssid)
            status = "Saved ✅"
            let wifi = MinerWifiConnection(ssid: ssid)
            modelContext.insert(wifi)
            onSave(wifi)
        } catch {
            status = error.localizedDescription
        }
    }

    private func loadIfExists() {
        do {
            if let stored = try KeychainHelper.load(account: ssid), !stored.isEmpty {
                password = stored
                status = "Loaded existing credentials"
            }
        } catch {
            status = error.localizedDescription
        }
    }
}

// MARK: - Preview
#Preview {
    WiFiCredentialsFormView(onSave: { _ in }, onCancel: {})
}
