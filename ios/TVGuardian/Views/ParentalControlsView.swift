import SwiftUI

struct ParentalControlsView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var name = ""
    @State private var age = 8
    var body: some View {
        Form {
            Section("Enforcement diagnostics") {
                ScopeNote()
                LabeledContent("Parent authentication", value: "Unlocked")
                LabeledContent("TV control channel", value: model.connected ? "Connected" : "Disconnected")
                LabeledContent("TV PIN / native lock state", value: "Unverified")
                Text("Stored rules survive app restarts. They run when this app evaluates a launch. iOS suspension and a disconnected TV prevent live monitoring; no background system enforcement is claimed.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Parent administrator") {
                Button(model.state.useFaceID ? "Disable Face ID" : "Enable Face ID") {
                    model.run("Face ID setting") {
                        if model.state.useFaceID { try KeychainStore.remove("administrator.biometryDomain"); try model.save { $0.useFaceID = false } }
                        else { try await model.admin.enableBiometrics(); try model.save { $0.useFaceID = true } }
                        try model.record("authentication", "saved", "Face ID preference changed by the parent.")
                    }
                }.disabled(model.busy)
                Button("Lock parent session") { model.lock() }
                Text("The administrator PIN is salted and derived with PBKDF2, and stored in the iOS Keychain. It is separate from the Samsung TV PIN.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Age-based Guardian profiles") {
                Picker("Active profile", selection: Binding(get: { model.state.activeProfileID }, set: { model.selectProfile($0) })) {
                    Text("No profile").tag(UUID?.none)
                    ForEach(model.state.profiles) { Text("\($0.name) • \($0.age)").tag(Optional($0.id)) }
                }
                TextField("Child profile name", text: $name)
                Stepper("Age: \(age)", value: $age, in: 0...21)
                Button("Add profile") { model.addProfile(name: name, age: age); name = "" }.disabled(model.busy)
            }
            Section("Policies") {
                NavigationLink("Per-app restrictions") { AppRestrictionsView() }
                NavigationLink("Bedtime and school-time schedules") { SchedulesView() }
                NavigationLink("Website and DNS Filtering") { DNSFilteringView() }
                FeatureRow(feature: .usage, evidence: .baseline(.usage))
                Text("Daily usage limits are unavailable because no reliable TV-wide usage source or authorized enforcement mechanism is available. Controller activity logs are not viewing-time measurements.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Parental Controls")
    }
}

struct SchedulesView: View {
    @EnvironmentObject private var model: GuardianModel
    var initialAppID: String? = nil
    @State private var editing: RestrictionSchedule?
    @State private var deleting: RestrictionSchedule?
    var body: some View {
        List {
            Section { ScopeNote(title: "Guardian launch schedules", text: "Schedules deny new launches through this iPhone app. They do not stop an app already running or enforce bedtime on the TV's physical remote.") }
            Section("Saved schedules") {
                let schedules = model.state.schedules.filter { $0.tvID == model.state.selectedTVID }
                if schedules.isEmpty { Text("No schedules for this TV.").foregroundStyle(.secondary) }
                ForEach(schedules) { schedule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Button(schedule.name) { editing = schedule }; Spacer(); Text(RuleEngine.isActive(schedule, at: Date()) ? "Active now" : "Inactive").font(.caption).foregroundStyle(.secondary) }
                        Text("\(clock(schedule.startMinute))–\(clock(schedule.endMinute)) • \(schedule.timeZoneID)").font(.footnote)
                        Text(schedule.weekdays.sorted().map { ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][$0] }.joined(separator: ", ") + (schedule.startMinute == schedule.endMinute ? " • All day" : "")).font(.caption).foregroundStyle(.secondary)
                        Text(schedule.appID.flatMap { id in model.selectedTV?.apps.first { $0.id == id }?.name ?? id } ?? "All Guardian launches").font(.caption)
                        Toggle("Enabled", isOn: Binding(get: { schedule.enabled }, set: { value in var changed = schedule; changed.enabled = value; model.saveSchedule(changed) })).disabled(model.busy)
                        Button("Delete schedule", role: .destructive) { deleting = schedule }.font(.footnote)
                    }
                }
            }
            Section {
                Button("Add schedule") {
                    guard let tv = model.selectedTV else { model.errorMessage = "Select a TV first."; return }
                    editing = RestrictionSchedule(tvID: tv.id, appID: initialAppID, name: "Bedtime", weekdays: Array(1...7), startMinute: 21 * 60, endMinute: 7 * 60, timeZoneID: TimeZone.current.identifier)
                }.disabled(model.busy || model.selectedTV == nil)
                Text("Overnight windows belong to their start day. End time is exclusive. Equal start and end times mean all day. The saved home time zone stays fixed when you travel.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Screen-Time Schedules")
            .sheet(item: $editing) { ScheduleEditor(schedule: $0) }
            .confirmationDialog("Delete this Guardian schedule?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete schedule", role: .destructive) { if let id = deleting?.id { model.deleteSchedule(id) }; deleting = nil }
            }
    }
    private func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

struct ScheduleEditor: View {
    @EnvironmentObject private var model: GuardianModel
    @Environment(\.dismiss) private var dismiss
    @State var schedule: RestrictionSchedule
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Guardian-only restriction") {
                    TextField("Name", text: $schedule.name)
                    Picker("Scope", selection: Binding(get: { schedule.appID ?? "" }, set: { schedule.appID = $0.isEmpty ? nil : $0 })) {
                        Text("All Guardian launches").tag("")
                        ForEach(model.selectedTV?.apps ?? []) { Text($0.name).tag($0.id) }
                    }
                    Picker("Starts", selection: $schedule.startMinute) { ForEach(0..<1440, id: \.self) { Text(String(format: "%02d:%02d", $0 / 60, $0 % 60)).tag($0) } }
                    Picker("Ends", selection: $schedule.endMinute) { ForEach(0..<1440, id: \.self) { Text(String(format: "%02d:%02d", $0 / 60, $0 % 60)).tag($0) } }
                    TextField("Home time zone", text: $schedule.timeZoneID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Use an IANA identifier, for example Asia/Muscat. Overnight times belong to the selected start days.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Start days") {
                    ForEach(1...7, id: \.self) { day in Toggle(days[day - 1], isOn: Binding(get: { schedule.weekdays.contains(day) }, set: { on in schedule.weekdays.removeAll { $0 == day }; if on { schedule.weekdays.append(day) } })) }
                }
                ScopeNote()
            }.navigationTitle("Edit schedule").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { model.saveSchedule(schedule); dismiss() }.disabled(schedule.name.isEmpty || schedule.weekdays.isEmpty || TimeZone(identifier: schedule.timeZoneID) == nil || model.busy) }
            }
        }
    }
}
