import Foundation

enum SupportStatus: String, Codable, CaseIterable { case supported, unsupported, unverified }

enum Feature: String, Codable, CaseIterable, Identifiable {
    case inventory, launch, close, uninstall, nativeLock, preventReinstall
    case usage, nativeSchedules, networkSettings, remote, controllerRules, dns
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inventory: return "Installed app discovery"
        case .launch: return "Direct app launch"
        case .close: return "Direct app close"
        case .uninstall: return "Direct uninstall"
        case .nativeLock: return "TV app lock / unlock"
        case .preventReinstall: return "Prevent reinstallation"
        case .usage: return "TV-wide usage and limits"
        case .nativeSchedules: return "TV-wide schedule enforcement"
        case .networkSettings: return "Lock TV network settings"
        case .remote: return "Authenticated remote channel"
        case .controllerRules: return "TV Guardian launch restrictions"
        case .dns: return "DNS provider rules"
        }
    }
}

struct CapabilityEvidence: Codable, Equatable {
    var status: SupportStatus
    var reason: String
    var checkedAt: Date? = nil
    var route: String
    static func baseline(_ feature: Feature) -> Self {
        let reasons: [Feature: String] = [
            .uninstall: "Samsung's TV Package API requires platform signing. Use the TV-side deletion guide.",
            .nativeLock: "No verified public API for native app locks or the Samsung TV PIN. Set up on the TV.",
            .preventReinstall: "No authorized installer policy API is available to this controller.",
            .usage: "No reliable TV-wide usage feed; TV Web usage-history APIs are mobile-only.",
            .nativeSchedules: "iOS and a public foreground companion cannot enforce a system-wide schedule.",
            .networkSettings: "No verified public API to lock network settings.",
            .controllerRules: "Rules are evaluated before launches through this app only. Other remotes bypass them."
        ]
        if let reason = reasons[feature] {
            return Self(status: feature == .controllerRules ? .supported : .unsupported,
                        reason: reason, route: "Public API boundary")
        }
        return Self(status: .unverified, reason: "No response has verified this operation for this TV and firmware.", route: "Awaiting device response")
    }
}

enum AppOrigin: String, Codable { case samsungWebSocket, companion }
enum InstallationKind: String, Codable { case system, user, unknown }

struct TVApplication: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var origin: AppOrigin
    var launchID: String? = nil
    var packageID: String? = nil
    var iconURL: String? = nil
    var iconPath: String? = nil
    var installationKind: InstallationKind = .unknown
    var appType: Int? = nil
    var launchEvidence: CapabilityEvidence? = nil
    var closeEvidence: CapabilityEvidence? = nil
}

struct TVRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var host: String
    var model: String = "Unknown"
    var firmware: String = "Unknown"
    var firmwareSource: String? = nil
    var parentModelCode: String? = nil
    var deviceIdentity: String? = nil
    var lastSeen: Date? = nil
    var inventoryAt: Date? = nil
    var apps: [TVApplication] = []
    var capabilities: [String: CapabilityEvidence] = [:]
    func evidence(_ feature: Feature) -> CapabilityEvidence {
        capabilities[feature.rawValue] ?? .baseline(feature)
    }
}

struct ChildProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var age: Int
}

struct AppRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var tvID: UUID
    var appID: String
    var blocked: Bool = false
    /// A parent-assigned threshold, not an official content rating.
    var minimumAge: Int? = nil
}

struct RestrictionSchedule: Identifiable, Codable, Equatable {
    var id = UUID()
    var tvID: UUID
    var appID: String? = nil
    var name: String
    /// Calendar weekday: Sunday = 1 ... Saturday = 7. Overnight windows belong to the start day.
    var weekdays: [Int]
    var startMinute: Int
    var endMinute: Int
    var timeZoneID: String
    var enabled = true
}

struct LaunchDecision: Equatable {
    var allowed: Bool
    var reason: String
}

struct AuditEvent: Identifiable, Codable {
    var id = UUID()
    var timestamp = Date()
    var category: String
    var outcome: String
    var detail: String
    var previousMAC: String
    var mac: String
}

enum DNSProvider: String, Codable, CaseIterable, Identifiable {
    case adguardHome, piHole6, nextDNS
    var id: String { rawValue }
    var title: String {
        switch self { case .adguardHome: return "AdGuard Home"; case .piHole6: return "Pi-hole v6"; case .nextDNS: return "NextDNS" }
    }
}

struct DNSConfiguration: Codable, Equatable {
    var provider: DNSProvider = .piHole6
    var baseURL: String = ""
    var username: String = ""
    var profileID: String = ""
    /// Pi-hole group assignment is explicit. Group 0 is the default group.
    var piHoleGroup: Int = 0
    /// AdGuard rules use this exact client IP; no global rule is created.
    var clientIP: String = ""
}

struct DNSQuery: Identifiable {
    var id = UUID()
    var domain: String
    var client: String
    var result: String
    var time: String
}

struct GuardianState: Codable {
    var schemaVersion = 1
    var tvs: [TVRecord] = []
    var selectedTVID: UUID? = nil
    var profiles: [ChildProfile] = []
    var activeProfileID: UUID? = nil
    var rules: [AppRule] = []
    var schedules: [RestrictionSchedule] = []
    var dns = DNSConfiguration()
    var bridgeURL = ""
    var companionID = ""
    var companionTVID: UUID? = nil
    var useFaceID = false
}

enum GuardianError: LocalizedError {
    case invalid(String), unavailable(String), denied(String), protocolError(String)
    case trustRequired(host: String, fingerprint: String), certificateChanged
    var errorDescription: String? {
        switch self {
        case .invalid(let s), .unavailable(let s), .denied(let s), .protocolError(let s): return s
        case .trustRequired(let host, let fingerprint): return "Review the certificate for \(host): \(fingerprint)"
        case .certificateChanged: return "The TV certificate changed. Connection blocked. Verify the TV and remove its pairing before trusting a new certificate."
        }
    }
}
