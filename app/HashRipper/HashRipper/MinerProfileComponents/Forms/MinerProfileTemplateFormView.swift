import SwiftUI
import SwiftData

struct MinerProfileTemplateFormView: View {

    // MARK: – Environment
    @Environment(\.modelContext) private var modelContext

    // MARK: – Form state
    @State private var name: String = ""
    @State private var templateNotes: String = ""

    @State private var stratumURL: String = ""
    @State private var stratumPort: Int = 0
    @State private var poolAccount: String = ""
    @State private var parasiteLightningAddress: String = ""
    @State private var stratumPassword: String = ""

    @State private var fallbackURL: String = ""
    @State private var fallbackPort: Int    = 0
    @State private var fallbackAccount: String = ""
    @State private var fallbackParasiteLightningAddress: String = ""
    @State private var fallbackStratumPassword: String = ""

    let onSave: (MinerProfileTemplate) -> Void
    let onCancel: () -> Void

    init(
        name: String,
        templateNotes: String,
        stratumURL: String,
        stratumPort: Int,
        poolAccount: String,
        parasiteLightningAddress: String? = nil,
        stratumPassword: String,
        fallbackURL: String? = nil,
        fallbackPort: Int? = nil,
        fallbackAccount: String? = nil,
        fallbackParasiteLightningAddress: String? = nil,
        fallbackStratumPassword: String? = nil,
        onSave: @escaping (MinerProfileTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.name = name
        self.templateNotes = templateNotes
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.poolAccount = poolAccount
        self.parasiteLightningAddress = parasiteLightningAddress ?? ""
        self.stratumPassword = stratumPassword
        self.fallbackURL = fallbackURL ?? ""
        self.fallbackPort = fallbackPort ?? 0
        self.fallbackAccount = fallbackAccount ?? ""
        self.fallbackParasiteLightningAddress = fallbackParasiteLightningAddress ?? ""
        self.fallbackStratumPassword = fallbackStratumPassword ?? ""

        self.onSave = onSave
        self.onCancel = onCancel
    }


    init(onSave: @escaping (MinerProfileTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
    }
    // MARK: – Body
    var body: some View {
        VStack(alignment: .leading) {
            ScrollView {
                VStack {
                    Text("Create a template with all the pool settings you want to apply to miners. This can be used for quickly onbaording new miners to your cluser or rolled out to your existing miners when a change is needed.")
                }.padding(12)
                Form {
                    // Template meta
                    Section {

                        TextField(
                            "Name",
                            text: $name,
                            prompt: Text("Name of the miner profile (e.g. Bitaxe · Local Pool - f2Pool fallback)"), axis: .vertical)
                        TextField("Notes", text: $templateNotes, prompt: Text("Any details you might want about this profile"),axis: .vertical,)
                            .lineLimit(3...50)

                    }
                    //                .padding(.bottom, 18)

                    Spacer().frame(height: 24)

                    // Primary pool
                    Section(header: PoolSectionHeaderContent(title: "Primary Pool", isParasitePool: isParasitePool(stratumURL))) {
                        TextField("Stratum URL", text: $stratumURL, prompt: Text("Pool url leave out any 'stratum+tcp://' prefix"))
                        TextField("Port",       value: $stratumPort, formatter: NumberFormatter())
#if os(iOS) || os(tvOS) || os(visionOS)
                            .keyboardType(.numberPad)
#endif

                            TextField("Account / BTC Address", text: $poolAccount).padding(.bottom, 0)
                        if isParasitePool(stratumURL) {
                            TextField("Parasite ⚡️ Address", text: $parasiteLightningAddress)
                            Text("The miner will be setup with the stratum user <account>.<miner-name>.<parasite-lightning-address>@parasite.sati.pro during the setup process.").font(.caption)
                        } else {
                            Text("The miner will be setup with the stratum user <account>.<miner name> during the setup process.").font(.caption)
                        }

                            TextField("Stratum Password", text: $stratumPassword)
                    }

                    Spacer().frame(height: 24)
                    // Fallback pool
                    Section(header: PoolSectionHeaderContent(title: "Fallback Pool (Optional · All or none is saved)", isParasitePool: isParasitePool(fallbackURL))) {
                        TextField("URL",  text: $fallbackURL)
                        TextField("Port", value: $fallbackPort, formatter: NumberFormatter())
#if os(iOS) || os(tvOS) || os(visionOS)
                            .keyboardType(.numberPad)
#endif
//                        ZStack {
                            TextField("Account / BTC Address", text: $fallbackAccount)
                        if isParasitePool(fallbackURL) {
                            TextField("Parasite ⚡️ Address", text: $fallbackParasiteLightningAddress)
                            Text("The miner will be setup with the stratum user <account>.<miner-name>.<parasite-lightning-address>@parasite.sati.pro during the setup process.").font(.caption)
                        } else {
                            Text("The miner will be setup with the stratum user <account>.<miner name> during the setup process.").font(.caption)//.offset(y: 20)
                        }

                            TextField("Password", text: $fallbackStratumPassword)
//                        }
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
                .navigationTitle("New Miner Profile")
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: saveTemplate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                Spacer()
            }.frame(height: 64,)
                .padding(.horizontal, 24)
        }
//            .formStyle(.grouped)
        
    }

    // MARK: – Validation

    private var isFormValid: Bool {
        let sanitizedStratumUrl = stratumURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sanitizedStratumUrl.isEmpty
            && stratumPort > 0
            && ( !isParasitePool(sanitizedStratumUrl)
                 || ( isParasitePool(sanitizedStratumUrl)
                      && !parasiteLightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            && !stratumPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !poolAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: – Persistence
    private func saveTemplate() {
        guard stratumPort > 0 else { return }
        let sanitizedStratumUrl = stratumURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedFallbackUrl = fallbackURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let addFallback = !sanitizedFallbackUrl.isEmpty
            && (
                !isParasitePool(sanitizedFallbackUrl) || isParasitePool(sanitizedFallbackUrl) &&
                !parasiteLightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            && fallbackPort != 0
            && !fallbackAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !fallbackStratumPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let template = MinerProfileTemplate(
            name:               name.trimmingCharacters(in: .whitespacesAndNewlines),
            templateNotes:      templateNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            stratumURL:         sanitizedStratumUrl,
            poolAccount:        poolAccount.trimmingCharacters(in: .whitespacesAndNewlines),
            parasiteLightningAddress: isParasitePool(stratumURL) ? parasiteLightningAddress : nil,
            stratumPort:        stratumPort,
            stratumPassword: stratumPassword,
            fallbackStratumURL:     addFallback ? fallbackURL.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            fallbackStratumAccount: addFallback  ? fallbackAccount.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            fallbackParasiteLightningAddress: isParasitePool(fallbackURL) ? fallbackParasiteLightningAddress : nil,
            fallbackStatrumPassword: addFallback ? fallbackStratumPassword.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            fallbackStratumPort:    addFallback ? fallbackPort : nil
        )
        defer {
            onSave(template)
        }
        do {
            modelContext.insert(template)
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save template: \(error)")
        }
    }
}


struct PoolSectionHeaderContent: View {
    @Environment(\.openURL) var openURL

    let title: String
    let isParasitePool: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
            if (isParasitePool) {
                HStack {
                    Spacer()
                    Image("parasiteIcon").resizable().frame(width: 16, height: 16)
                    Text("Parasite Setup Instructions")
                        .underline()
                        .foregroundStyle(Color.orange)
                }
                .contentShape(Rectangle())
                .pointerStyle(.link)
                .onTapGesture {
                    openURL(URL(string: "https://www.solosatoshi.com/how-to-connect-your-bitaxe-to-parasite-pool/?from=HashRipper")!)
                }
            }

            
            // link to parasite setup

        }
    }

}
