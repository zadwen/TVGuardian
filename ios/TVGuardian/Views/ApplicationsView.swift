import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var search = ""
    var apps: [TVApplication] { (model.selectedTV?.apps ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section {
                if let tv = model.selectedTV {
                    Text(tv.name).font(.headline)
                    if let date = tv.inventoryAt { Text("Saved inventory: \(date.formatted()). Refresh to check for changes.").font(.footnote).foregroundStyle(.secondary) }
                    Text("Inventory may omit protected apps. System/user status is shown only when known; Samsung's public metadata does not establish it.").font(.footnote).foregroundStyle(.secondary)
                    Button("Refresh direct app inventory") { model.refreshApps() }.disabled(model.busy)
                } else { NavigationLink("Connect a TV first") { ConnectedTVsView() } }
            }
            if apps.isEmpty {
                Section { ContentUnavailableView("No app entries", systemImage: "app.dashed", description: Text("Connect and refresh. If this TV does not return apps, try the foreground Tizen companion. No sample inventory is shown.")) }
            } else {
                Section("Reported applications") {
                    ForEach(apps) { app in
                        NavigationLink { ApplicationDetailView(appID: app.id) } label: {
                            HStack(spacing: 12) {
                                TVAppIcon(app: app)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name).font(.callout.bold())
                                    Text(app.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(app.installationKind == .unknown ? "Installation type unknown" : app.installationKind.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let tv = model.selectedTV, !RuleEngine.evaluate(tvID: tv.id, appID: app.id, state: model.state).allowed { Image(systemName: "hand.raised.fill").foregroundStyle(.orange).accessibilityLabel("Restricted in TV Guardian") }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Installed Applications").searchable(text: $search, prompt: "Name or app identifier")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { CompanionView() } label: { Image(systemName: "link") }.accessibilityLabel("Companion inventory") } }
    }
}

struct ApplicationDetailView: View {
    @EnvironmentObject private var model: GuardianModel
    let appID: String
    @State private var blocked = false
    @State private var minimumAge = 0
    @State private var confirmClose = false
    var app: TVApplication? { model.selectedTV?.apps.first { $0.id == appID } }
    var body: some View {
        Form {
            if let app, let tv = model.selectedTV {
                Section {
                    HStack(spacing: 14) { TVAppIcon(app: app); VStack(alignment: .leading, spacing: 5) { Text(app.name).font(.title3.bold()); Text(app.id).font(.caption).textSelection(.enabled) } }
                    LabeledContent("Source", value: app.origin == .companion ? "Tizen companion" : "Samsung WebSocket")
                    LabeledContent("Installation type", value: app.installationKind.rawValue.capitalized)
                    if let package = app.packageID { LabeledContent("Package identifier", value: package).font(.footnote).textSelection(.enabled) }
                    if model.icons[app.id] == nil { Text("No usable icon was returned. Local companion icon paths are not exposed as network URLs.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Direct operations") {
                    Button("Launch app") { model.launch(app) }.disabled(model.busy || app.launchID == nil)
                    FeatureRow(feature: .launch, evidence: app.launchEvidence ?? .baseline(.launch))
                    if app.launchID == nil { Text("No verified Samsung launch ID for this companion entry. IDs are not translated by guessing.").font(.footnote).foregroundStyle(.secondary) }
                    Button("Attempt direct close") { confirmClose = true }.disabled(model.busy || app.launchID == nil)
                    FeatureRow(feature: .close, evidence: app.closeEvidence ?? .baseline(.close))
                    NavigationLink("Uninstall on TV — guided steps") { TVGuideView(kind: .deleteApp) }
                    FeatureRow(feature: .uninstall, evidence: .baseline(.uninstall))
                }
                Section("Native TV lock") {
                    FeatureRow(feature: .nativeLock, evidence: .baseline(.nativeLock))
                    NavigationLink("Set up lock / unlock on the TV") { TVGuideView(kind: .appLock) }
                }
                Section("TV Guardian launch rule") {
                    ScopeNote()
                    Toggle("Block in TV Guardian", isOn: $blocked)
                    Picker("Parent-assigned minimum age", selection: $minimumAge) { Text("No age threshold").tag(0); ForEach(1...21, id: \.self) { Text("\($0)+").tag($0) } }
                    Text("Age thresholds use the active Guardian profile and your own judgment. They are not Samsung content ratings.").font(.footnote).foregroundStyle(.secondary)
                    Button("Save Guardian rule") { model.setRule(appID: app.id, blocked: blocked, minimumAge: minimumAge == 0 ? nil : minimumAge) }.disabled(model.busy)
                    Text(RuleEngine.evaluate(tvID: tv.id, appID: app.id, state: model.state).reason).font(.footnote)
                    NavigationLink("Restrict by schedule") { SchedulesView(initialAppID: app.id) }
                }
                Section("Management permissions") {
                    ForEach([Feature.preventReinstall, .usage, .nativeSchedules], id: \.self) { FeatureRow(feature: $0, evidence: tv.evidence($0)) }
                }
            } else { ContentUnavailableView("App entry unavailable", systemImage: "app.dashed", description: Text("The saved inventory changed. Return to Installed Applications.")) }
        }
        .navigationTitle(app?.name ?? "Application").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let rule = model.state.rules.first(where: { $0.tvID == model.state.selectedTVID && $0.appID == appID }) { blocked = rule.blocked; minimumAge = rule.minimumAge ?? 0 }
        }
        .confirmationDialog("Close this TV app?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Request close", role: .destructive) { if let app { model.close(app) } }
        } message: { Text("This community-observed REST operation is unverified until the TV reports a stopped state. It may interrupt viewing. It does not uninstall the app.") }
    }
}

struct AppRestrictionsView: View {
    @EnvironmentObject private var model: GuardianModel
    var body: some View {
        List {
            Section { ScopeNote() }
            Section("Saved Guardian restrictions") {
                let rules = model.state.rules.filter { $0.tvID == model.state.selectedTVID && ($0.blocked || $0.minimumAge != nil) }
                if rules.isEmpty { Text("No rules saved for this TV.").foregroundStyle(.secondary) }
                ForEach(rules) { rule in
                    NavigationLink { ApplicationDetailView(appID: rule.appID) } label: {
                        VStack(alignment: .leading, spacing: 5) { Text(model.selectedTV?.apps.first { $0.id == rule.appID }?.name ?? rule.appID); Text(rule.blocked ? "Blocked in Guardian" : "Parent threshold \(rule.minimumAge ?? 0)+").font(.caption).foregroundStyle(.orange) }
                    }
                }
                NavigationLink("Manage applications and rules") { ApplicationsView() }
            }
            Section("TV-side protection") {
                NavigationLink("Native app lock / unlock setup") { TVGuideView(kind: .appLock) }
                NavigationLink("Change the Samsung TV PIN") { TVGuideView(kind: .tvPIN) }
                FeatureRow(feature: .preventReinstall, evidence: .baseline(.preventReinstall))
                NavigationLink("Reinstallation and physical-access limits") { TVGuideView(kind: .bypass) }
            }
        }.navigationTitle("App Restrictions")
    }
}
