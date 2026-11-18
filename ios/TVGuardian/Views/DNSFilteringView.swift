import SwiftUI

struct DNSFilteringView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var config = DNSConfiguration()
    @State private var credential = ""
    @State private var domain = ""
    @State private var preview: DNSChangePreview?
    @State private var queries: [DNSQuery] = []
    var body: some View {
        Form {
            Section { ScopeNote(title: "DNS is a separate layer", text: "A domain deny rule is not a Tizen app lock. DNS cannot reliably stop native apps, encrypted DNS, VPNs, IP-based traffic, caches or offline content. Router settings must direct TV traffic through the configured resolver.") }
            Section("Provider configuration") {
                Picker("Provider", selection: $config.provider) { ForEach(DNSProvider.allCases) { Text($0.title).tag($0) } }
                if config.provider == .nextDNS {
                    TextField("NextDNS profile ID", text: $config.profileID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Use a dedicated TV profile if other devices should not share these restrictions. The NextDNS API is documented as beta.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    TextField("HTTPS origin, no path", text: $config.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("TV reserved IPv4 (log filter)", text: $config.clientIP).keyboardType(.decimalPad)
                }
                if config.provider == .adguardHome { TextField("AdGuard username", text: $config.username).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if config.provider == .piHole6 {
                    Stepper("Pi-hole group ID: \(config.piHoleGroup)", value: $config.piHoleGroup, in: 0...9999)
                    Text("Assign the TV to the selected group in Pi-hole. Group 0 commonly includes other clients. Use an application password with API modifications enabled. v5 APIs are not supported.").font(.footnote).foregroundStyle(.secondary)
                }
                SecureField(config.provider == .nextDNS ? "API key (leave empty to retain)" : "Application password (leave empty to retain)", text: $credential).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save configuration & credential") {
                    model.run("save DNS configuration") {
                        if config.provider != .nextDNS { _ = try Validation.httpsBase(config.baseURL) }
                        if !credential.isEmpty { try model.dns.storeCredential(credential, config: config) }
                        try model.save { $0.dns = config }; credential = ""
                        try model.record("DNS configuration", "saved", "DNS provider configuration saved. Resolver deployment and TV routing are external requirements.")
                        model.notice = "Configuration saved. Preview a rule or load queries to test the provider connection."
                    }
                }.disabled(model.busy)
                Text("TLS must be trusted by iOS. Install your home CA on the phone if needed; certificates are never ignored for DNS services.").font(.footnote).foregroundStyle(.secondary)
                Text("Credentials are bound to the saved HTTPS origin and account/profile. Changing either requires saving its credential again.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Domain rules • saved configuration") {
                TextField("example.com", text: $domain).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Preview block rule") { prepare(blocking: true) }.disabled(model.busy)
                Button("Preview deny-rule removal") { prepare(blocking: false) }.disabled(model.busy || model.state.dns.provider == .piHole6)
                Text("Removing a deny rule does not override another filter, policy or native app restriction. Pi-hole removals require group-aware review in its own dashboard.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Recent DNS events • up to 100") {
                Button("Load provider queries") { model.run("read DNS queries") { queries = try await model.dns.queries(model.state.dns); try model.record("DNS logs", "received", "Provider query results loaded. Results may include other devices in the selected profile/group.") } }.disabled(model.busy)
                if queries.isEmpty { Text("No queries loaded. Provider logging, retention and TV DNS routing determine what is available.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(queries) { query in VStack(alignment: .leading, spacing: 4) { Text(query.domain).font(.callout.bold()); Text("\(query.result) • \(query.client)").font(.caption); Text(query.time).font(.caption2).foregroundStyle(.secondary) } }
            }
            Section("Router policies") {
                Text("No router model or authenticated policy API was supplied. Router policy writes are unsupported in this build. Configure client isolation, resolver assignment and egress controls through your router's supported administration tools.").font(.footnote)
                NavigationLink("Realistic bypass limits") { TVGuideView(kind: .bypass) }
            }
        }.navigationTitle("Website & DNS Filtering").onAppear { config = model.state.dns }.onDisappear { credential = "" }
            .sheet(item: $preview) { change in
                NavigationStack {
                    Form {
                        Section("Review network change") {
                            LabeledContent("Provider", value: change.config.provider.title)
                            LabeledContent("Domain", value: change.domain)
                            LabeledContent("Action", value: change.blocking ? "Add deny rule" : "Remove deny rule")
                            Text(change.scope)
                            if let rules = change.proposedRules { Text("Proposed custom rules (\(rules.count))").font(.caption); Text(rules.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            Text("This may affect other devices within the stated scope. DNS routing and actual app access have not been verified.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Apply reviewed provider change", role: .destructive) { model.applyDNS(change); preview = nil }.disabled(model.busy)
                    }.navigationTitle("Confirm DNS change").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { preview = nil } } }
                }
            }
    }
    private func prepare(blocking: Bool) { model.run("preview DNS change") { preview = try await model.dns.preview(config: model.state.dns, domain: domain, blocking: blocking) } }
}
