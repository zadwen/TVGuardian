import Foundation
import Combine

struct TVTrustReview: Identifiable { var id = UUID(); var tvID: UUID; var host: String; var fingerprint: String }

@MainActor final class GuardianModel: ObservableObject {
    @Published private(set) var state = GuardianState()
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var connectionMessage = "Disconnected"
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var trustReview: TVTrustReview?
    @Published private(set) var storageIssue: String?
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var icons: [String: Data] = [:]
    @Published private(set) var isParentUnlocked = false
    @Published private(set) var sessionID = UUID()
    let admin = Administrator()
    let discovery = DiscoveryService()
    let dns = DNSService()
    let smartThings = SmartThingsService()
    let companion = CompanionService()
    private let client = SamsungTVClient()
    private var store: StateStore?
    private var audit: AuditLog?
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var monitor: Task<Void, Never>?
    private var idleTimer: Timer?
    private var idleDeadline = Date()
    private var automaticReconnectSuspended = false
    private var authenticationObservation: AnyCancellable?
    var selectedTV: TVRecord? { state.tvs.first { $0.id == state.selectedTVID } }
    var profile: ChildProfile? { state.profiles.first { $0.id == state.activeProfileID } }
    init() {
        do {
            let store = try StateStore(); self.store = store; state = try store.load()
            let audit = try AuditLog(directory: store.directory); self.audit = audit; auditEvents = audit.events
        } catch { storageIssue = error.localizedDescription }
        admin.onAudit = { [weak self] outcome, detail in
            guard let self else { return }
            do { try self.record("authentication", outcome, detail) } catch { self.storageIssue = error.localizedDescription; self.lock() }
        }
        authenticationObservation = admin.$isUnlocked.removeDuplicates().sink { [weak self] unlocked in
            guard let self else { return }
            self.isParentUnlocked = unlocked
            self.sessionID = UUID()
            if unlocked { self.unlocked() } else { self.finishLock() }
        }
    }
    func touch() { idleDeadline = Date().addingTimeInterval(300) }
    func requireAccess() throws {
        try admin.requireUnlocked()
        guard storageIssue == nil, store != nil, audit != nil else { throw GuardianError.denied("Management is locked because saved data or audit integrity needs attention.") }
    }
    func record(_ category: String, _ outcome: String, _ detail: String) throws {
        guard let audit else { throw GuardianError.unavailable("Audit storage is unavailable.") }
        try audit.append(category: category, outcome: outcome, detail: detail); auditEvents = audit.events
    }
    func save(_ change: (inout GuardianState) throws -> Void) throws {
        try requireAccess()
        var next = state; try change(&next)
        guard let store else { throw GuardianError.unavailable("Saved-state storage is unavailable.") }
        try store.save(next); state = next
    }
    func run(_ category: String, userInitiated: Bool = true, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { notice = "Wait for the current operation to finish."; return }
        do { try requireAccess(); if userInitiated { touch() }; try record(category, "requested", "\(userInitiated ? "Parent" : "Foreground reconnect") initiated \(category).") }
        catch { errorMessage = error.localizedDescription; return }
        busy = true; let id = UUID(); operationID = id
        operation = Task {
            do {
                try Task.checkCancellation(); try await action()
            } catch {
                if !Task.isCancelled {
                    if !client.isConnected { connected = false; connectionMessage = "Disconnected — inspect the operation error" }
                    if !userInitiated {
                        self.connectionMessage = "Automatic reconnect failed. Use Connected TVs to inspect pairing and identity."
                        if case GuardianError.certificateChanged = error { self.automaticReconnectSuspended = true }
                        if case GuardianError.denied = error { self.automaticReconnectSuspended = true }
                    } else if case GuardianError.trustRequired(let host, let fingerprint) = error,
                       let tv = state.tvs.first(where: { $0.host == host }) {
                        trustReview = TVTrustReview(tvID: tv.id, host: host, fingerprint: fingerprint)
                    } else { errorMessage = error.localizedDescription }
                    do { try record(category, "failed", "The operation did not produce a verified success. Review the displayed error.") }
                    catch { storageIssue = error.localizedDescription; lock() }
                }
            }
            if operationID == id { busy = false; operation = nil; operationID = nil }
        }
    }
    func lock() {
        let wasAlreadyLocked = !admin.isUnlocked
        admin.lock()
        if wasAlreadyLocked { finishLock() }
    }
    private func finishLock() {
        operation?.cancel(); operation = nil; operationID = nil; busy = false
        monitor?.cancel(); monitor = nil; client.disconnect(); discovery.stop()
        idleTimer?.invalidate(); idleTimer = nil
        connected = false; connectionMessage = "Locked — TV channel disconnected"
        trustReview = nil; notice = nil; errorMessage = nil; icons = [:]
    }
    private func unlocked() {
        touch()
        connectionMessage = "Disconnected — select a TV to connect"
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.admin.isUnlocked else { return }
                if Date() >= self.idleDeadline { self.lock() }
            }
        }
        monitor?.cancel()
        monitor = Task {
            var retryDelay: UInt64 = 2
            while !Task.isCancelled && admin.isUnlocked {
                do { try await Task.sleep(nanoseconds: retryDelay * 1_000_000_000) } catch { return }
                guard !Task.isCancelled, admin.isUnlocked else { return }
                if Date() > idleDeadline { lock(); return }
                guard !busy, let tv = selectedTV else { retryDelay = 20; continue }
                if client.isConnected {
                    do { try await client.ping(); connected = true; retryDelay = 20 }
                    catch { client.disconnect(); connected = false; connectionMessage = "Connection lost — retrying while unlocked"; retryDelay = 2 }
                } else {
                    guard !automaticReconnectSuspended, (try? KeychainStore.string("tv.\(tv.id).token")) != nil else { retryDelay = 20; continue }
                    run("automatic TV reconnection", userInitiated: false) { try await self.establish(tv, allowPairing: false) }
                    retryDelay = min(30, retryDelay * 2)
                }
            }
        }
    }
    private func updateTV(_ id: UUID, _ change: (inout TVRecord) -> Void) throws {
        try save { state in
            guard let index = state.tvs.firstIndex(where: { $0.id == id }) else { throw GuardianError.invalid("TV no longer exists.") }
            change(&state.tvs[index])
        }
    }
    private func establish(_ tv: TVRecord, allowPairing: Bool) async throws {
        try requireAccess()
        let metadata = try await client.inspect(tv)
        if let previous = tv.deviceIdentity, metadata.identity != previous {
            throw GuardianError.denied("The device identity at this IP changed or is no longer reported. Pair it as a new TV; existing credentials were not sent.")
        }
        try Task.checkCancellation(); try requireAccess()
        try await client.connect(tv, allowPairing: allowPairing)
        try Task.checkCancellation(); try requireAccess()
        try updateTV(tv.id) { record in
            if record.model != metadata.model || (metadata.firmware != nil && record.firmware != metadata.firmware) {
                record.capabilities = [:]; record.apps = []; record.inventoryAt = nil
            }
            record.name = metadata.name; record.model = metadata.model
            if let firmware = metadata.firmware { record.firmware = firmware; record.firmwareSource = "TV metadata response" }
            record.deviceIdentity = metadata.identity ?? record.deviceIdentity
            record.lastSeen = Date()
            record.capabilities[Feature.remote.rawValue] = CapabilityEvidence(status: .supported, reason: "The TV returned ms.channel.connect over its reviewed TLS channel. Individual key effects are not observable.", checkedAt: Date(), route: "Samsung WebSocket / port 8002")
        }
        connected = true; connectionMessage = "Connected securely to \(metadata.name)"
    }
    @discardableResult func addTV(host: String, name: String) -> Bool {
        do {
            try requireAccess()
            guard !busy else { throw GuardianError.unavailable("Wait for the current operation before saving this TV.") }
            let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Validation.privateIPv4(address) else { throw GuardianError.invalid("Enter a private IPv4 TV address, such as 192.168.1.50. Public addresses and URLs are rejected.") }
            try record("save TV", "requested", "Parent requested saving a private TV address.")
            if let existing = state.tvs.first(where: { $0.host == address }) {
                try save { $0.selectedTVID = existing.id }
            } else {
                let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let tv = TVRecord(name: label.isEmpty ? "Samsung TV" : String(label.prefix(80)), host: address)
                try save { $0.tvs.append(tv); $0.selectedTVID = tv.id }
            }
            client.disconnect(); connected = false; icons = [:]
            connectionMessage = "TV saved — ready to pair"
            notice = "TV saved. Tap Pair / reconnect under Saved TVs."
            try record("save TV", "saved", "A private TV address was saved. It has not been paired or verified.")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    func selectTV(_ id: UUID) {
        guard !busy else { return }
        do { try save { $0.selectedTVID = id }; client.disconnect(); connected = false; icons = [:]; connectionMessage = "Disconnected" }
        catch { errorMessage = error.localizedDescription }
    }
    func pair() {
        run("pair TV") {
            self.automaticReconnectSuspended = false
            guard let tv = self.selectedTV else { throw GuardianError.invalid("Add or select a TV first.") }
            try await self.establish(tv, allowPairing: true)
            try self.record("pair TV", "verified", "Authenticated encrypted TV channel connected.")
            self.notice = "Connected. Refresh Installed Applications to test this firmware's inventory support."
        }
    }
    func approveTrust(_ review: TVTrustReview) {
        run("trust TV certificate") {
            guard let tv = self.selectedTV, tv.id == review.tvID, tv.host == review.host else { throw GuardianError.invalid("Select the TV whose certificate was reviewed.") }
            guard try KeychainStore.string("tv.\(tv.id).pin") == nil else { throw GuardianError.denied("Existing pins cannot be replaced silently. Remove the pairing first.") }
            try KeychainStore.writeString(review.fingerprint, account: "tv.\(tv.id).pin")
            try self.record("TLS trust", "saved", "Parent approved a specific TV leaf certificate on the private network.")
            self.trustReview = nil; self.notice = "Certificate saved. Tap Pair / reconnect and approve the TV prompt."
        }
    }
    func forgetTV(_ id: UUID) {
        run("remove local TV pairing") {
            self.client.disconnect(); self.connected = false
            try KeychainStore.remove("tv.\(id).token"); try KeychainStore.remove("tv.\(id).pin")
            try self.save {
                $0.tvs.removeAll { $0.id == id }; $0.rules.removeAll { $0.tvID == id }; $0.schedules.removeAll { $0.tvID == id }
                if $0.selectedTVID == id { $0.selectedTVID = $0.tvs.first?.id }
                if $0.companionTVID == id { $0.companionTVID = nil; $0.companionID = "" }
            }
            try self.record("remove local TV pairing", "saved", "Local pairing and associated controller rules removed. TV access must also be revoked in Device Connect Manager.")
        }
    }
    func refreshApps() {
        run("app discovery") {
            guard let tv = self.selectedTV else { throw GuardianError.invalid("Select a TV first.") }
            if !self.client.isConnected || self.client.connectedTVID != tv.id { try await self.establish(tv, allowPairing: false) }
            let apps = try await self.client.installedApplications()
            try self.updateTV(tv.id) { record in
                let ids = Set(apps.map(\.id))
                record.apps = apps + record.apps.filter { $0.origin == .companion && !ids.contains($0.id) }
                record.inventoryAt = Date()
                record.capabilities[Feature.inventory.rawValue] = CapabilityEvidence(status: .supported, reason: "TV returned \(apps.count) launchable entries. This is not a complete package inventory; missing apps may require the companion.", checkedAt: Date(), route: "ed.installedApp.get")
            }
            try self.record("app discovery", "verified", "Received \(apps.count) TV app entries. Completeness is not guaranteed.")
            for app in apps.prefix(60) {
                try Task.checkCancellation()
                let downloaded = try? await self.client.icon(app)
                if let downloaded { self.icons[app.id] = downloaded }
            }
        }
    }
    func launch(_ app: TVApplication) {
        run("launch app") {
            guard let tv = self.selectedTV else { throw GuardianError.invalid("Select a TV.") }
            let initial = RuleEngine.evaluate(tvID: tv.id, appID: app.id, state: self.state)
            guard initial.allowed else { try self.record("launch app", "blocked", "A controller restriction denied the launch."); throw GuardianError.denied(initial.reason) }
            if !self.client.isConnected || self.client.connectedTVID != tv.id { try await self.establish(tv, allowPairing: false) }
            guard self.selectedTV?.apps.contains(where: { $0.id == app.id && $0.launchID == app.launchID }) == true else { throw GuardianError.unavailable("Inventory changed during reconnect. Refresh before launching an app from this firmware.") }
            let decision = RuleEngine.evaluate(tvID: tv.id, appID: app.id, state: self.state)
            guard decision.allowed else { try self.record("launch app", "blocked", "A controller restriction denied the launch."); throw GuardianError.denied(decision.reason) }
            try self.requireAccess(); try await self.client.launch(app)
            try self.record("launch app", "submitted", "Direct launch command submitted for \(app.id).")
            self.notice = "Launch command sent. TV execution is unverified."
            // A status response is evidence only for this app ID and firmware.
            try await Task.sleep(nanoseconds: 800_000_000)
            if let running = try? await self.client.status(app), running {
                try self.updateTV(tv.id) { record in
                    let evidence = CapabilityEvidence(status: .supported, reason: "The REST status endpoint reported app \(app.id) running after a direct launch request. Other apps may differ.", checkedAt: Date(), route: "ed.apps.launch + REST status")
                    record.capabilities[Feature.launch.rawValue] = evidence
                    if let index = record.apps.firstIndex(where: { $0.id == app.id }) { record.apps[index].launchEvidence = evidence }
                }
                try self.record("launch app", "observed", "The TV reported \(app.id) running after the request.")
                self.notice = "The TV reported this app running after the launch request."
            }
        }
    }
    func close(_ app: TVApplication) {
        run("close app") {
            guard let tv = self.selectedTV else { throw GuardianError.invalid("Select a TV.") }
            if !self.client.isConnected || self.client.connectedTVID != tv.id { try await self.establish(tv, allowPairing: false) }
            guard self.selectedTV?.apps.contains(where: { $0.id == app.id && $0.launchID == app.launchID }) == true else { throw GuardianError.unavailable("Refresh the changed inventory before closing an app.") }
            let changed = try await self.client.close(app)
            if changed {
                try self.updateTV(tv.id) { record in
                    if let index = record.apps.firstIndex(where: { $0.id == app.id }) {
                        record.apps[index].closeEvidence = CapabilityEvidence(status: .supported, reason: "Running → stopped was observed after REST DELETE for this app. This does not uninstall the app.", checkedAt: Date(), route: "REST close + status read-back")
                    }
                }
                try self.record("close app", "observed", "Running-to-stopped transition observed for \(app.id). No package was uninstalled.")
                self.notice = "App stopped according to TV status. It remains installed."
            } else { self.notice = "The TV already reports this app stopped. No close was sent." }
        }
    }
    func key(_ key: RemoteKey) {
        run("remote command") {
            guard let tv = self.selectedTV else { throw GuardianError.invalid("Select a TV.") }
            if !self.client.isConnected || self.client.connectedTVID != tv.id { try await self.establish(tv, allowPairing: false) }
            try await self.client.key(key)
            try self.record("remote command", "submitted", "Sent \(key.rawValue). Physical effect is not verified.")
        }
    }
    func setRule(appID: String, blocked: Bool, minimumAge: Int?) {
        run("save restriction") {
            guard let tv = self.selectedTV else { throw GuardianError.invalid("Select a TV.") }
            try self.save { state in
                state.rules.removeAll { $0.tvID == tv.id && $0.appID == appID }
                state.rules.append(AppRule(tvID: tv.id, appID: appID, blocked: blocked, minimumAge: minimumAge))
            }
            try self.record("restriction", "saved", "Controller launch rule saved for \(appID). Native TV lock state is unchanged and unknown.")
        }
    }
    func addProfile(name: String, age: Int) {
        run("save child profile") {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (0...21).contains(age) else { throw GuardianError.invalid("Enter a profile name and age from 0 to 21.") }
            let profile = ChildProfile(name: String(name.prefix(40)), age: age)
            try self.save { $0.profiles.append(profile); $0.activeProfileID = profile.id }
            try self.record("profile", "saved", "A parent-created age profile was saved. It is not a Samsung account or official content rating.")
        }
    }
    func selectProfile(_ id: UUID?) {
        do { try save { $0.activeProfileID = id }; try record("profile", "saved", "Active controller profile changed.") }
        catch { errorMessage = error.localizedDescription }
    }
    func saveSchedule(_ schedule: RestrictionSchedule) {
        run("save schedule") {
            guard !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  TimeZone(identifier: schedule.timeZoneID) != nil, (0..<1440).contains(schedule.startMinute), (0..<1440).contains(schedule.endMinute), !schedule.name.isEmpty else { throw GuardianError.invalid("Complete the schedule and select at least one day.") }
            try self.save { $0.schedules.removeAll { $0.id == schedule.id }; $0.schedules.append(schedule) }
            try self.record("schedule", "saved", "A controller-only schedule was saved with a fixed home time zone.")
        }
    }
    func deleteSchedule(_ id: UUID) {
        run("delete schedule") {
            try self.save { $0.schedules.removeAll { $0.id == id } }
            try self.record("schedule", "saved", "A controller schedule was removed.")
        }
    }
    func applyDNS(_ preview: DNSChangePreview) {
        run("DNS rule change") {
            let result = try await self.dns.apply(preview)
            if let tv = self.selectedTV {
                try self.updateTV(tv.id) { $0.capabilities[Feature.dns.rawValue] = CapabilityEvidence(status: .supported, reason: "A provider rule response was verified at \(preview.config.provider.title). TV routing, bypass resistance and native app access remain unverified.", checkedAt: Date(), route: "DNS provider API") }
            }
            try self.record("DNS", "provider verified", "\(preview.blocking ? "Added" : "Removed") a domain deny rule at \(preview.config.provider.title). TV app access is not verified.")
            self.notice = result
        }
    }
    func importCompanion(_ report: CompanionReport) {
        run("associate companion inventory") {
            guard let tv = self.selectedTV, !report.stale, let snapshot = report.snapshot,
                  snapshot.inventoryStatus == "supported" else { throw GuardianError.unavailable("A fresh, successful companion inventory is required. The companion may be suspended or denied access.") }
            let apps = snapshot.apps.map { TVApplication(id: $0.id, name: $0.name, origin: .companion, packageID: $0.packageID, iconPath: $0.iconPath) }
            try self.updateTV(tv.id) { record in
                let direct = record.apps.filter { $0.origin == .samsungWebSocket }
                let directIDs = Set(direct.map(\.id)); record.apps = direct + apps.filter { !directIDs.contains($0.id) }
                record.inventoryAt = Date()
                record.capabilities[Feature.inventory.rawValue] = CapabilityEvidence(status: .supported, reason: "A parent-associated companion returned public API inventory. It may omit protected apps and does not identify system status.", checkedAt: Date(), route: "Foreground Tizen companion")
            }
            try self.save { $0.companionID = report.companionID; $0.companionTVID = tv.id }
            try self.record("companion", "received", "Parent associated \(apps.count) companion app identifiers with the selected TV. Launch identifiers were not guessed.")
            self.notice = "Companion inventory imported. Launch requires a separately reported Samsung WebSocket ID."
        }
    }
    func exportAudit() -> URL? {
        do { try requireAccess(); return try audit?.export() } catch { errorMessage = error.localizedDescription; return nil }
    }
}
