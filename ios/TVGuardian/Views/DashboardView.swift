import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: GuardianModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack { Image(systemName: "shield.lefthalf.filled").font(.largeTitle); Spacer(); Text("PARENT SESSION").font(.caption.weight(.bold)) }
                    Text(model.selectedTV?.name ?? "Your home, your rules").font(.title.bold())
                    Label(model.connectionMessage, systemImage: model.connected ? "wifi" : "wifi.slash").font(.callout)
                    NavigationLink("Manage connection") { ConnectedTVsView() }.buttonStyle(.bordered)
                }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Color(red: 0.02, green: 0.35, blue: 0.38), Color(red: 0.02, green: 0.18, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                ScopeNote()
                HStack(spacing: 12) {
                    metric("App entries", value: "\(model.selectedTV?.apps.count ?? 0)", symbol: "app.badge")
                    metric("Guardian rules", value: "\(model.state.rules.filter { $0.tvID == model.state.selectedTVID && ($0.blocked || $0.minimumAge != nil) }.count)", symbol: "hand.raised")
                }
                Text("Manage your TV").font(.title3.bold())
                VStack(spacing: 0) {
                    NavigationLink { ApplicationsView() } label: { dashboardRow("Installed Applications", subtitle: "Discover, launch and inspect management permissions", icon: "app.badge") }
                    Divider()
                    NavigationLink { AppRestrictionsView() } label: { dashboardRow("App Restrictions", subtitle: "Saved rules and native lock setup", icon: "lock.shield") }
                    Divider()
                    NavigationLink { SchedulesView() } label: { dashboardRow("Screen-Time Schedules", subtitle: "Bedtime and school-time launch rules", icon: "calendar.badge.clock") }
                }.padding(.horizontal).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                if let tv = model.selectedTV {
                    Text("Compatibility evidence").font(.title3.bold())
                    ForEach([Feature.inventory, .launch, .uninstall, .nativeLock], id: \.self) { FeatureRow(feature: $0, evidence: tv.evidence($0)) }
                }
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("TV Guardian")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { model.lock() } label: { Image(systemName: "lock.fill") }.accessibilityLabel("Lock parent session") } }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).foregroundStyle(.teal); Text(value).font(.title.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private func dashboardRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(.teal); VStack(alignment: .leading, spacing: 4) { Text(title).font(.callout.bold()).foregroundStyle(.primary); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 17)
    }
}

struct MoreView: View {
    var body: some View {
        List {
            Section("Manage") {
                NavigationLink { ConnectedTVsView() } label: { Label("Connected TVs", systemImage: "tv") }
                NavigationLink { AppRestrictionsView() } label: { Label("App Restrictions", systemImage: "lock.app.dashed") }
                NavigationLink { SchedulesView() } label: { Label("Screen-Time Schedules", systemImage: "calendar") }
                NavigationLink { DNSFilteringView() } label: { Label("Website and DNS Filtering", systemImage: "network") }
                NavigationLink { TVSettingsView() } label: { Label("TV Settings", systemImage: "gearshape") }
                NavigationLink { RemoteControlView() } label: { Label("Remote Control", systemImage: "appletvremote.gen1") }
            }
            Section("Integrations & evidence") {
                NavigationLink { CompanionView() } label: { Label("TV Companion", systemImage: "link") }
                NavigationLink { SmartThingsView() } label: { Label("SmartThings capability access", systemImage: "cloud") }
                NavigationLink { ActivityView() } label: { Label("Activity and Security Logs", systemImage: "list.bullet.rectangle") }
                NavigationLink { CompatibilityView() } label: { Label("Compatibility", systemImage: "checkmark.shield") }
                NavigationLink { RemoteAccessView() } label: { Label("VPN Remote Access", systemImage: "network") }
            }
        }.navigationTitle("Manage & inspect")
    }
}
