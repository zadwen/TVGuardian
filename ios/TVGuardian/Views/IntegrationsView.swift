import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var bridgeURL = ""
    @State private var token = ""
    @State private var pairing: CompanionPairing?
    @State private var reports: [CompanionReport] = []
    @State private var association: CompanionReport?
    @State private var revoke: CompanionReport?
    var body: some View {
        Form {
            Section { ScopeNote(title: "Optional public Tizen companion", text: "The foreground companion reads public app inventory and reports permission errors over HTTPS. It cannot uninstall, lock apps, stop reinstallation or survive being closed as an enforcement service.") }
            Section("Home bridge") {
                TextField("HTTPS bridge origin", text: $bridgeURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Parent bridge token (empty retains)", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save bridge connection") {
                    model.run("save bridge configuration") {
                        _ = try Validation.httpsBase(bridgeURL)
                        if !token.isEmpty {
                            guard token.count >= 40 else { throw GuardianError.invalid("Use the high-entropy parent token created by the bridge setup command.") }
                            try model.companion.storeParentToken(token, base: bridgeURL)
                        }
                        try model.save { $0.bridgeURL = bridgeURL }; token = ""
                        try model.record("companion", "saved", "HTTPS bridge configuration saved; no privileged TV operations are enabled.")
                    }
                }.disabled(model.busy)
                Text("Build and run the included bridge on an always-on home computer. Both the TV and iPhone must trust its TLS certificate. The token is bound to this HTTPS origin; changing it requires entering that bridge's token.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Pair a foreground TV companion") {
                Button("Create one-time pairing code") { model.run("open companion pairing") { pairing = try await model.companion.openPairing(base: model.state.bridgeURL) } }.disabled(model.busy)
                if let pairing {
                    Text(pairing.code).font(.system(.title2, design: .monospaced).bold()).textSelection(.enabled)
                    Text("Enter this code in the companion on the TV. Expires: \(pairing.expiresAt). Use the same bridge HTTPS origin.").font(.footnote)
                }
                Text("The code is single-use and short-lived. The TV token stays in memory for this foreground session and expires within eight hours.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Companion reports") {
                Button("Refresh reports & health") { model.run("read companion reports") { reports = try await model.companion.reports(base: model.state.bridgeURL) } }.disabled(model.busy)
                if reports.isEmpty { Text("No reports loaded.").foregroundStyle(.secondary) }
                ForEach(reports, id: \.companionID) { report in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.name).font(.headline)
                        Text("\(report.stale ? "Stale / not enforcing" : "Fresh inventory report") • \(report.receivedAt)").font(.caption).foregroundStyle(report.stale ? .orange : .secondary)
                        Text("Inventory status: \(report.snapshot?.inventoryStatus ?? "unverified"). Entries: \(report.snapshot?.apps.count ?? 0). Completeness not guaranteed.").font(.footnote)
                        ForEach(report.snapshot?.errors ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        Button("Associate inventory with selected TV") { association = report }.disabled(model.busy || report.stale || model.selectedTV == nil)
                        Button("Revoke companion session", role: .destructive) { revoke = report }.font(.footnote)
                    }
                }
                Text("No automatic identity mapping is assumed. Associate only the companion you just opened on the selected TV. A fresh inventory report is not evidence of parental enforcement.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("TV Companion").onAppear { bridgeURL = model.state.bridgeURL }.onDisappear { token = "" }
            .confirmationDialog("Associate this companion?", isPresented: Binding(get: { association != nil }, set: { if !$0 { association = nil } }), titleVisibility: .visible) {
                Button("Associate with \(model.selectedTV?.name ?? "selected TV")") { if let report = association { model.importCompanion(report) }; association = nil }
            } message: { Text("Confirm this report came from the selected TV. Tizen IDs will remain distinct from Samsung launch IDs unless they match exactly.") }
            .confirmationDialog("Revoke companion access?", isPresented: Binding(get: { revoke != nil }, set: { if !$0 { revoke = nil } }), titleVisibility: .visible) {
                Button("Revoke session", role: .destructive) {
                    if let report = revoke { model.run("revoke companion") { try await model.companion.revoke(base: model.state.bridgeURL, id: report.companionID); reports.removeAll { $0.companionID == report.companionID }; try model.record("companion", "revoked", "Parent revoked a companion bearer session.") } }
                    revoke = nil
                }
            }
    }
}

struct SmartThingsView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var token = ""
    @State private var devices: [SmartThingsDevice] = []
    @State private var removeToken = false
    var body: some View {
        Form {
            Section("Optional official cloud API") {
                Text("SmartThings exposes the capabilities registered for each device. It is not an installed-app manager and does not provide a verified uninstall, native lock or TV PIN API.").font(.footnote)
                SecureField("Authorized access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save access token in Keychain") {
                    model.run("save SmartThings token") {
                        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { throw GuardianError.invalid("Enter an authorized access token without whitespace.") }
                        try KeychainStore.writeString(token, account: "smartthings.accessToken"); token = ""
                        try model.record("SmartThings", "saved", "User-supplied access token stored in Keychain.")
                    }
                }.disabled(model.busy)
                Text("Samsung documents new personal access tokens as valid for 24 hours. An App Store distribution needs your registered OAuth service integration; no client secret is embedded in this app. Check current developer-account access requirements.").font(.footnote).foregroundStyle(.secondary)
                Link("Official authorization documentation", destination: URL(string: "https://developer.smartthings.com/docs/getting-started/authorization-and-permissions")!)
                Button("Remove saved cloud token", role: .destructive) { removeToken = true }.disabled(model.busy)
            }
            Section("Choose the exact cloud device") {
                Button("Load authorized devices") { model.run("read SmartThings devices") { devices = try await model.smartThings.devices(); try model.record("SmartThings", "received", "Loaded authorized cloud devices. No TV identity was automatically inferred.") } }.disabled(model.busy)
                ForEach(devices) { device in NavigationLink(device.label ?? device.name ?? device.id) { CloudDeviceView(device: device) } }
            }
        }.navigationTitle("SmartThings").onDisappear { token = "" }
            .confirmationDialog("Remove the phone's cloud token?", isPresented: $removeToken, titleVisibility: .visible) {
                Button("Remove local token", role: .destructive) { model.run("remove SmartThings token") { try KeychainStore.remove("smartthings.accessToken"); devices = []; try model.record("SmartThings", "removed", "Cloud token removed from this phone. Revoke it in the provider account separately.") } }
            }
    }
}

struct CloudDeviceView: View {
    @EnvironmentObject private var model: GuardianModel
    let device: SmartThingsDevice
    @State private var status = "No status loaded."
    @State private var off = false
    @State private var volume = 20
    @State private var inputs: [String] = []
    @State private var selectedInput = ""
    var body: some View {
        List {
            Section("Device") { Text(device.id).font(.caption).textSelection(.enabled); Text("This selection is separate from the locally paired TV. Confirm the device identity before sending commands.").font(.footnote).foregroundStyle(.secondary) }
            Section("Advertised capabilities") {
                ForEach(device.components ?? [], id: \.id) { component in ForEach(component.capabilities, id: \.id) { Text("\(component.id) / \($0.id) v\($0.version)").font(.caption) } }
            }
            if device.supports("switch") {
                Section("Switch capability") {
                    Button("Request power on") { sendPower(true) }.disabled(model.busy)
                    Button("Request power off", role: .destructive) { off = true }.disabled(model.busy)
                    Text("A cloud command acknowledgement does not prove the TV changed state. Refresh status to inspect the provider's observation.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if device.supports("audioVolume") {
                Section("Advertised volume capability") {
                    Stepper("Requested volume: \(volume)", value: $volume, in: 0...100)
                    Button("Submit volume setting") {
                        model.run("cloud volume request") {
                            try await model.smartThings.volume(volume, device: device)
                            try model.record("SmartThings command", "acknowledged", "Provider acknowledged a volume request for the selected device. Physical effect is unverified.")
                            model.notice = "Volume request acknowledged. Refresh status to inspect the provider observation."
                        }
                    }.disabled(model.busy)
                }
            }
            if device.supports("mediaInputSource") {
                Section("Advertised input capability") {
                    Button("Load reported input sources") {
                        model.run("read cloud input sources") { inputs = try await model.smartThings.supportedInputs(device); selectedInput = inputs.first ?? "" }
                    }.disabled(model.busy)
                    if !inputs.isEmpty {
                        Picker("Input", selection: $selectedInput) { ForEach(inputs, id: \.self) { Text($0).tag($0) } }
                        Button("Submit input change") {
                            model.run("cloud input request") {
                                try await model.smartThings.input(selectedInput, device: device)
                                try model.record("SmartThings command", "acknowledged", "Provider acknowledged a reported input source request. Guardian app rules do not constrain input changes.")
                                model.notice = "Input request acknowledged. Physical state is unverified."
                            }
                        }.disabled(model.busy)
                    }
                    Text("Only standard mediaInputSource values reported by this device are offered. Vendor-specific capabilities and empty source lists remain unverified.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Provider status") {
                Button("Refresh status") { model.run("read cloud device status") { status = try await model.smartThings.status(device) } }.disabled(model.busy)
                Text(status).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }.navigationTitle(device.label ?? "Cloud device").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Power off this cloud device?", isPresented: $off, titleVisibility: .visible) { Button("Submit power off request", role: .destructive) { sendPower(false) } }
    }
    private func sendPower(_ on: Bool) {
        model.run("cloud power request") {
            try await model.smartThings.power(on, device: device)
            try model.record("SmartThings command", "acknowledged", "Provider acknowledged a switch command for the explicitly selected cloud device. Physical state is unverified.")
            model.notice = "SmartThings acknowledged the request. Refresh provider status to inspect the result."
        }
    }
}
