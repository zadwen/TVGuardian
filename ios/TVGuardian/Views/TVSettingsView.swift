import SwiftUI

enum TVGuideKind { case appLock, deleteApp, tvPIN, bypass }
struct TVGuideView: View {
    let kind: TVGuideKind
    var title: String {
        switch kind { case .appLock: return "Native app locks"; case .deleteApp: return "Delete an app on TV"; case .tvPIN: return "Samsung TV PIN"; case .bypass: return "Bypass protection" }
    }
    var steps: [String] {
        switch kind {
        case .appLock: return ["On the TV, open Home → Apps → Settings (gear). Menu names vary by model and firmware.", "Choose the app, then Lock or Unlock. Enter the Samsung TV PIN on the TV.", "Try opening the app with the physical remote to verify the PIN prompt. Check each app separately.", "Keep your TV PIN private. TV Guardian cannot read or change the native lock state through a verified public API."]
        case .deleteApp: return ["On the TV, open Home → Apps → Settings (gear). Select the unwanted app.", "Choose Delete and confirm on the TV. If Delete is unavailable, treat the app as protected; do not use service menus or firmware modifications.", "Refresh TV Guardian's inventory afterward. Disappearance from a partial inventory alone is not proof of uninstall.", "Deleting an app does not prevent reinstallation. A system update or Samsung policy may also restore apps."]
        case .tvPIN: return ["Open TV Settings → General / General & Privacy → System Manager → Change PIN. Consult your model's manual when the menu differs.", "Choose a private Samsung TV PIN on the TV. This is separate from TV Guardian's administrator PIN.", "Review native app locks and any broadcast programme-rating lock available on your model. Broadcast ratings are not universal app-content controls.", "Test the restrictions with the physical remote. This app cannot verify the TV PIN or prevent physical factory reset."]
        case .bypass: return ["Use native app locks for apps children can open with the physical remote. Also review AirPlay, casting, HDMI sources and allowed external controllers on the TV.", "Protect the router administrator account. Use a reserved TV IP, a dedicated network or VLAN, and apply router rules to the TV. This project has no verified universal router policy API.", "DNS filtering can be bypassed through other networks, encrypted DNS, VPNs, hardcoded IPs, caches and offline content. Blocking ports 53/853 alone does not stop DNS-over-HTTPS.", "A public companion can be closed or suspended and cannot prevent its own removal. Missing heartbeats indicate loss of reporting, not a successful policy lock.", "Physical access, TV administrator access, router administrator access or factory reset can defeat these controls. Reinstallation prevention and TV network-setting locks remain unsupported through this app."]
        }
    }
    var body: some View {
        List {
            Section { ScopeNote(title: "Guided TV-side setup", text: "These steps require you to operate the TV. TV Guardian does not send a direct uninstall, lock or PIN-management command.") }
            Section("Steps") { ForEach(Array(steps.enumerated()), id: \.offset) { index, step in HStack(alignment: .top, spacing: 12) { Text("\(index + 1)").font(.headline).foregroundStyle(.teal); Text(step) }.padding(.vertical, 5) } }
            Section { Link("Samsung's official app management guide", destination: URL(string: "https://www.samsung.com/uk/support/tv-audio-video/how-do-i-manage-apps-on-my-smart-tv/")!) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct TVSettingsView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var modelCode = ""
    @State private var firmware = ""
    var body: some View {
        Form {
            if let tv = model.selectedTV {
                Section("Reported device details") {
                    LabeledContent("Name", value: tv.name)
                    LabeledContent("Private IP", value: tv.host)
                    LabeledContent("API model value", value: tv.model)
                    LabeledContent("Parent-reported full model code", value: tv.parentModelCode ?? "Not supplied")
                    LabeledContent("Firmware", value: tv.firmware)
                    Text("Firmware source: \(tv.firmwareSource ?? "Not reported or verified")").font(.caption).foregroundStyle(.secondary)
                    Text("The supplied photo shows a friendly SmartThings label only. Verify the full model code and software version on the TV under Support → About This TV.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Record firmware from the TV") {
                    TextField("Full model code from About This TV", text: $modelCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Software version from About This TV", text: $firmware).textInputAutocapitalization(.never)
                    Button("Save parent-reported firmware") {
                        model.run("record firmware") {
                            guard !firmware.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GuardianError.invalid("Enter the software version shown by the TV.") }
                            try model.save { state in
                                guard let i = state.tvs.firstIndex(where: { $0.id == tv.id }) else { return }
                                state.tvs[i].firmware = String(firmware.prefix(100)); state.tvs[i].firmwareSource = "Parent reported"
                                state.tvs[i].parentModelCode = modelCode.isEmpty ? nil : String(modelCode.prefix(100)); state.tvs[i].capabilities = [:]
                                state.tvs[i].apps = []; state.tvs[i].inventoryAt = nil
                            }
                            try model.record("compatibility", "parent reported", "Firmware recorded from parent input; cached capability evidence cleared.")
                            model.notice = "Firmware recorded as parent-provided information. Reconnect and refresh to collect new evidence."
                        }
                    }.disabled(model.busy)
                }
            } else { NavigationLink("Connect a TV") { ConnectedTVsView() } }
            Section("Native TV settings") {
                NavigationLink("App lock and unlock") { TVGuideView(kind: .appLock) }
                NavigationLink("Samsung PIN and programme locks") { TVGuideView(kind: .tvPIN) }
                NavigationLink("Device and network bypass protections") { TVGuideView(kind: .bypass) }
                FeatureRow(feature: .networkSettings, evidence: .baseline(.networkSettings))
                Text("Use the physical TV settings for picture, sound, accounts and security. SmartThings offers only the capabilities your selected cloud device advertises.").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Inspect SmartThings capabilities") { SmartThingsView() }
            }
        }.navigationTitle("TV Settings").onAppear { firmware = model.selectedTV?.firmware == "Unknown" ? "" : model.selectedTV?.firmware ?? ""; modelCode = model.selectedTV?.parentModelCode ?? "" }
    }
}

struct CompatibilityView: View {
    @EnvironmentObject private var model: GuardianModel
    var body: some View {
        List {
            Section("Evidence scope") {
                Text("Supported means the documented controller behavior is available, or a relevant device/provider response was observed. Each row states its scope. Unsupported is a known public API boundary. Unverified means evidence is missing or an operation timed out.")
                if let tv = model.selectedTV { Text("\(tv.name) • \(tv.model) • firmware \(tv.firmware)").font(.footnote) }
                Text("No operation was tested on your TV during source development. Device evidence is collected only after you connect. Firmware changes invalidate cached observations.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Features") { ForEach(Feature.allCases) { FeatureRow(feature: $0, evidence: model.selectedTV?.evidence($0) ?? .baseline($0)) } }
            Section { Link("Samsung TV Package API privilege requirements", destination: URL(string: "https://developer.samsung.com/smarttv/develop/api-references/tizen-web-device-api-references/package-api.html")!) }
        }.navigationTitle("Compatibility")
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var export: URL?
    var body: some View {
        List {
            Section {
                Text("These logs record parent actions, requests and observed API responses. They do not record every TV app launch or measure viewing time.").font(.footnote)
                Text("Saved entries are HMAC chained. Whole-file deletion or rollback is not detectable without an external witness. The latest 5,000 entries are retained.").font(.footnote).foregroundStyle(.secondary)
                Button("Prepare audit export") { export = model.exportAudit() }
                if let export { ShareLink(item: export) { Label("Share audit JSON", systemImage: "square.and.arrow.up") } }
            }
            Section("Latest 250 entries") {
                ForEach(Array(model.auditEvents.suffix(250).reversed())) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(event.category.capitalized).font(.callout.bold()); Spacer(); Text(event.outcome).font(.caption).foregroundStyle(.teal) }
                        Text(event.detail).font(.footnote)
                        Text(event.timestamp.formatted()).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("Activity & Security")
    }
}

struct RemoteAccessView: View {
    var body: some View {
        List {
            Section("Use your existing VPN") {
                Text("1. Install Tailscale on an always-on home computer/router and on your iPhone, or configure a WireGuard server and iPhone tunnel.")
                Text("2. For Tailscale, advertise and approve the TV's home subnet using a subnet router. Restrict access to the parent identity and only the addresses/ports you need.")
                Text("3. Connect the iPhone VPN and use the saved private TV IP. Bonjour discovery usually stays on the local network. The app validates the same TV certificate over the tunnel.")
                Text("4. The phone and TV must still reach the bridge or DNS service securely if you use those integrations. The TV itself does not need a VPN client for inbound subnet routing.")
            }
            Section { ScopeNote(title: "Network boundary", text: "Do not forward TV ports 8001/8002 or SDB 26101 to the internet. TV Guardian uses the VPN installed by you; it does not create or manage a VPN tunnel.") }
            Section {
                Link("Tailscale subnet router documentation", destination: URL(string: "https://tailscale.com/docs/features/subnet-routers")!)
                Link("WireGuard official setup", destination: URL(string: "https://www.wireguard.com/quickstart/")!)
            }
        }.navigationTitle("VPN Remote Access")
    }
}
