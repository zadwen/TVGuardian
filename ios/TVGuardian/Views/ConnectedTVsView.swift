import SwiftUI

struct ConnectedTVsView: View {
    @EnvironmentObject private var model: GuardianModel
    var body: some View { ConnectionForm(model: model, discovery: model.discovery) }
}

struct ConnectionForm: View {
    @ObservedObject var model: GuardianModel
    @ObservedObject var discovery: DiscoveryService
    @State private var host = ""
    @State private var name = ""
    @State private var removal: TVRecord?
    var body: some View {
        Form {
            Section("Saved TVs") {
                if model.state.tvs.isEmpty { Text("No TVs saved. Add a private IP or choose a discovery candidate.").foregroundStyle(.secondary) }
                ForEach(model.state.tvs) { tv in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { model.selectTV(tv.id) } label: { HStack { Text(tv.name); Spacer(); if model.state.selectedTVID == tv.id { Image(systemName: "checkmark.circle.fill") } } }
                        Text("\(tv.host) • \(tv.model)").font(.caption).foregroundStyle(.secondary)
                        if model.state.selectedTVID == tv.id {
                            Button("Pair / reconnect") { model.pair() }.disabled(model.busy)
                            Button("Remove local pairing & rules", role: .destructive) { removal = tv }.font(.footnote)
                        }
                    }.padding(.vertical, 4)
                }
                Text(model.connectionMessage).font(.footnote)
            }
            Section("Discover on this network") {
                Button("Find TVs") { discovery.start() }.disabled(model.busy)
                Text(discovery.status).font(.footnote).foregroundStyle(.secondary)
                ForEach(discovery.devices) { device in
                    Button { model.addTV(host: device.host, name: device.name) } label: { VStack(alignment: .leading) { Text(device.name); Text("\(device.host) • \(device.source)").font(.caption).foregroundStyle(.secondary) } }
                }
                Text("Discovery uses Bonjour. TVs that do not advertise these services need a manual IP. Wi-Fi client isolation and denied iOS Local Network permission can prevent discovery.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Manual private IP") {
                TextField("TV name", text: $name).textInputAutocapitalization(.words)
                TextField("192.168.1.50", text: $host).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save TV") { model.addTV(host: host.trimmingCharacters(in: .whitespacesAndNewlines), name: name) }.disabled(model.busy)
                Text("Find the TV IP under its Network Status settings. Reserve the address in your router. Port 8002 must be reachable locally or through your VPN.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Pairing") {
                Text("Turn on the TV. Review its TLS fingerprint in TV Guardian, then tap Pair and approve the connection prompt on the TV. Manage allowed devices in Samsung Device Connect Manager; exact menus vary by firmware.")
                Text("Metadata is read after certificate review. The screenshot's display name alone cannot verify your model or firmware.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Connected TVs").onDisappear { discovery.stop() }
            .confirmationDialog("Remove the local pairing?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                Button("Remove pairing and its Guardian rules", role: .destructive) { if let tv = removal { model.forgetTV(tv.id) }; removal = nil }
            } message: { Text("Saved app rules and schedules for this TV will be removed from the phone. Revoke this controller on the TV separately. No TV app is deleted.") }
    }
}
