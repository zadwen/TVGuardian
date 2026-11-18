import Foundation
import CryptoKit

struct StateStore {
    let directory: URL
    init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TVGuardian", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var mutable = self.directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }
    func load() throws -> GuardianState {
        let url = directory.appendingPathComponent("state-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return GuardianState() }
        let state = try JSONDecoder().decode(GuardianState.self, from: Data(contentsOf: url))
        try validate(state)
        return state
    }
    private func validate(_ state: GuardianState) throws {
        let tvIDs = Set(state.tvs.map(\.id)), profileIDs = Set(state.profiles.map(\.id))
        guard state.schemaVersion == 1, state.tvs.count <= 50, tvIDs.count == state.tvs.count,
              profileIDs.count == state.profiles.count, state.profiles.allSatisfy({ (0...21).contains($0.age) }),
              state.selectedTVID.map({ tvIDs.contains($0) }) ?? true,
              state.activeProfileID.map({ profileIDs.contains($0) }) ?? true,
              state.tvs.allSatisfy({ Validation.privateIPv4($0.host) && Set($0.apps.map(\.id)).count == $0.apps.count }),
              state.rules.allSatisfy({ tvIDs.contains($0.tvID) && ($0.minimumAge.map { (1...21).contains($0) } ?? true) }),
              state.schedules.allSatisfy({ tvIDs.contains($0.tvID) && !$0.weekdays.isEmpty && $0.weekdays.allSatisfy { (1...7).contains($0) }
                  && (0..<1440).contains($0.startMinute) && (0..<1440).contains($0.endMinute) && TimeZone(identifier: $0.timeZoneID) != nil }) else {
            throw GuardianError.unavailable("Saved policy data is inconsistent or uses an unsupported version. Preserve it for investigation; management is locked.")
        }
    }
    func save(_ state: GuardianState) throws {
        try validate(state)
        let data = try JSONEncoder().encode(state)
        try data.write(to: directory.appendingPathComponent("state-v1.json"), options: [.atomic, .completeFileProtection])
    }
}

/// HMAC chaining detects local alteration. This is not a remotely witnessed,
/// append-only record: deletion or rollback of the entire file is not detectable.
@MainActor final class AuditLog {
    private(set) var events: [AuditEvent] = []
    private var anchor = ""
    private let url: URL
    private let key: SymmetricKey
    private struct Envelope: Codable { var anchor: String; var events: [AuditEvent] }
    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }
    init(directory: URL) throws {
        url = directory.appendingPathComponent("audit-v1.json")
        if let saved = try KeychainStore.read("audit.hmac") { key = SymmetricKey(data: saved) }
        else {
            guard !FileManager.default.fileExists(atPath: url.path) else { throw GuardianError.unavailable("Audit key missing. Existing logs cannot be verified.") }
            let bytes = try KeychainStore.random(count: 32)
            try KeychainStore.write(bytes, account: "audit.hmac"); key = SymmetricKey(data: bytes)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
            var previous = envelope.anchor
            for event in envelope.events {
                guard event.previousMAC == previous, try Self.mac(event, key: key) == event.mac else {
                    throw GuardianError.unavailable("Audit integrity check failed. Management is locked until the saved log is investigated.")
                }
                previous = event.mac
            }
            anchor = envelope.anchor; events = envelope.events
        }
    }
    private static func mac(_ event: AuditEvent, key: SymmetricKey) throws -> String {
        var unsigned = event; unsigned.mac = ""
        return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(unsigned), using: key)).base64EncodedString()
    }
    func append(category: String, outcome: String, detail: String) throws {
        var event = AuditEvent(category: category, outcome: outcome, detail: String(detail.prefix(600)), previousMAC: events.last?.mac ?? anchor, mac: "")
        event.mac = try Self.mac(event, key: key)
        var next = events; next.append(event)
        var nextAnchor = anchor
        if next.count > 5000 { nextAnchor = next.removeFirst().mac }
        try Self.encoder.encode(Envelope(anchor: nextAnchor, events: next)).write(to: url, options: [.atomic, .completeFileProtection])
        events = next; anchor = nextAnchor
    }
    func export() throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("TVGuardian-audit.json")
        try Self.encoder.encode(Envelope(anchor: anchor, events: events)).write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }
}
