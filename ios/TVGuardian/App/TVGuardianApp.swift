import SwiftUI

@main struct TVGuardianApp: App {
    @StateObject private var model = GuardianModel()
    var body: some Scene { WindowGroup { SessionView(model: model).environmentObject(model) } }
}

struct SessionView: View {
    @ObservedObject var model: GuardianModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            if let issue = model.storageIssue {
                ContentUnavailableView("Saved data needs attention", systemImage: "lock.trianglebadge.exclamationmark", description: Text(issue + " Management is locked; preserve the app data for investigation."))
            } else if model.isParentUnlocked { MainTabs().id(model.sessionID) }
            else { AdministratorGate(admin: model.admin, faceIDEnabled: model.state.useFaceID) }
            if scenePhase != .active {
                Color(.systemBackground).ignoresSafeArea()
                Label("TV Guardian", systemImage: "shield.lefthalf.filled").font(.title.bold())
            }
        }
        .tint(.teal)
        .background(UserActivityObserver { if model.isParentUnlocked { model.touch() } }.frame(width: 0, height: 0))
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in if model.isParentUnlocked { model.touch() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.lock() } }
        .alert("Operation needs attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(item: $model.trustReview) { review in CertificateReview(review: review) }
    }
}

struct AdministratorGate: View {
    @ObservedObject var admin: Administrator
    let faceIDEnabled: Bool
    @State private var pin = ""
    @State private var confirmation = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 58)).foregroundStyle(.teal).padding(.top, 50)
                Text("TV Guardian").font(.largeTitle.bold())
                Text(admin.hasPIN ? "Parent access" : "Create your parent PIN").font(.title2.weight(.semibold))
                Text("Manage your TV with clear limits and a protected parent session.").foregroundStyle(.secondary)
                SecureField("6–12 digit administrator PIN", text: $pin).keyboardType(.numberPad).textContentType(.password).textFieldStyle(.roundedBorder).accessibilityIdentifier("administratorPIN")
                if !admin.hasPIN {
                    SecureField("Confirm administrator PIN", text: $confirmation).keyboardType(.numberPad).textFieldStyle(.roundedBorder).accessibilityIdentifier("administratorPINConfirmation")
                    Text("This PIN belongs to TV Guardian. It does not change the Samsung TV PIN. A forgotten PIN has no in-app bypass.").font(.footnote).foregroundStyle(.secondary)
                }
                if let message = admin.message { Text(message).foregroundStyle(.red).font(.callout) }
                Button {
                    Task {
                        if admin.hasPIN { await admin.unlock(pin: pin) } else { await admin.enroll(pin: pin, confirmation: confirmation) }
                        pin = ""; confirmation = ""
                    }
                } label: { HStack { if admin.busy { ProgressView() }; Text(admin.hasPIN ? "Unlock" : "Create PIN").frame(maxWidth: .infinity) }.padding(8) }
                .buttonStyle(.borderedProminent).disabled(admin.busy).accessibilityIdentifier("unlockAdministrator")
                if admin.hasPIN && faceIDEnabled {
                    Button { Task { await admin.unlockWithFaceID() } } label: { Label("Unlock with Face ID", systemImage: "faceid").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(admin.busy)
                }
                Text("Sessions lock when the app goes into the background or after five minutes without interaction.").font(.footnote).foregroundStyle(.secondary)
            }.padding(28)
        }
        .background(LinearGradient(colors: [.teal.opacity(0.10), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct MainTabs: View {
    @EnvironmentObject private var model: GuardianModel
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            NavigationStack { ApplicationsView() }.tabItem { Label("Apps", systemImage: "app.badge") }
            NavigationStack { ParentalControlsView() }.tabItem { Label("Protection", systemImage: "shield") }
            NavigationStack { MoreView() }.tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.busy { HStack(spacing: 10) { ProgressView(); Text("Working…").font(.caption); Spacer() }.padding(10).background(.thinMaterial) }
        }
        .safeAreaInset(edge: .bottom) {
            if let notice = model.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.footnote)
                    Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Dismiss notice")
                }.padding().background(.regularMaterial)
            }
        }
    }
}

struct CertificateReview: View {
    @EnvironmentObject private var model: GuardianModel
    @Environment(\.dismiss) private var dismiss
    let review: TVTrustReview
    var body: some View {
        NavigationStack {
            Form {
                Section("Trust this TV certificate") {
                    Text("The TV uses a certificate that iOS does not trust automatically. Confirm this private IP belongs to your TV on a network you trust. First-use trust does not independently prove the TV's identity.")
                    LabeledContent("Address", value: review.host + ":8002")
                    Text("SHA-256 leaf fingerprint").font(.caption)
                    Text(review.fingerprint).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    Text("A future certificate change will block the connection. Verify this fingerprint from a trusted computer where possible; see INSTALL.md.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Trust this certificate") { model.approveTrust(review); dismiss() }.disabled(model.busy)
            }
            .navigationTitle("Review TV trust").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
