import Foundation
import CryptoKit

struct DNSChangePreview: Identifiable {
    var id = UUID()
    var domain: String
    var blocking: Bool
    var scope: String
    var config: DNSConfiguration
    var expectedRules: [String]? = nil
    var proposedRules: [String]? = nil
}

@MainActor final class DNSService {
    private let http = SecureHTTPClient()
    private func account(_ config: DNSConfiguration) throws -> String {
        let identity = config.provider == .nextDNS ? config.profileID : config.username
        return try KeychainStore.scopedAccount("dns.\(config.provider.rawValue)", origin: base(config), identity: identity)
    }
    func storeCredential(_ value: String, config: DNSConfiguration) throws {
        guard !value.isEmpty else { throw GuardianError.invalid("Enter the provider credential.") }
        try KeychainStore.writeString(value, account: account(config))
    }
    private func secret(_ config: DNSConfiguration) throws -> String {
        guard let secret = try KeychainStore.string(account(config)), !secret.isEmpty else {
            throw GuardianError.denied("Save the provider credential for this exact HTTPS origin and account/profile first.")
        }
        if config.provider == .nextDNS && (secret.count > 4096 || secret.contains(where: { !$0.isASCII || $0.isWhitespace })) {
            throw GuardianError.invalid("The NextDNS API key is not a valid header credential.")
        }
        return secret
    }
    private func base(_ config: DNSConfiguration) throws -> URL {
        if config.provider == .nextDNS {
            guard config.profileID.count == 6, config.profileID.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw GuardianError.invalid("Enter the six-character NextDNS profile ID.") }
            return URL(string: "https://api.nextdns.io")!
        }
        return try Validation.httpsBase(config.baseURL)
    }
    private func basic(_ config: DNSConfiguration) throws -> [String: String] {
        guard !config.username.isEmpty, !config.username.contains(":"), !config.username.contains("\n") else { throw GuardianError.invalid("Enter the AdGuard Home username.") }
        return ["Authorization": "Basic " + Data("\(config.username):\(try secret(config))".utf8).base64EncodedString()]
    }
    private func piHole(_ config: DNSConfiguration, path: String, method: String = "GET", body: [String: Any]? = nil,
                        query: [URLQueryItem] = []) async throws -> [String: Any] {
        let origin = try base(config)
        let login = try await http.request(base: origin, path: "/api/auth", method: "POST", body: ["password": try secret(config)])
        guard let session = login["session"] as? [String: Any], session["valid"] as? Bool == true,
              let sid = session["sid"] as? String, !sid.isEmpty else {
            throw GuardianError.denied("Pi-hole v6 did not issue an authenticated session. Use a dedicated application password with API writes enabled.")
        }
        do {
            let result = try await http.request(base: origin, path: path, method: method, headers: ["X-FTL-SID": sid], body: body, query: query)
            _ = try? await http.request(base: origin, path: "/api/auth", method: "DELETE", headers: ["X-FTL-SID": sid])
            return result
        } catch {
            _ = try? await http.request(base: origin, path: "/api/auth", method: "DELETE", headers: ["X-FTL-SID": sid])
            throw error
        }
    }
    func preview(config: DNSConfiguration, domain rawDomain: String, blocking: Bool) async throws -> DNSChangePreview {
        let domain = try Validation.domain(rawDomain)
        _ = try base(config)
        switch config.provider {
        case .adguardHome:
            guard Validation.privateIPv4(config.clientIP) else { throw GuardianError.invalid("AdGuard requires the TV's reserved private IPv4 address to scope this rule.") }
            let result = try await http.request(base: base(config), path: "/control/filtering/status", headers: basic(config))
            guard let existing = result["user_rules"] as? [String], existing.count <= 50_000 else { throw GuardianError.protocolError("AdGuard did not return its custom rules. Nothing will be overwritten.") }
            let rule = "||\(domain)^$client=\(config.clientIP)"
            var next = existing.filter { $0 != rule }
            if blocking { next.append(rule) }
            return DNSChangePreview(domain: domain, blocking: blocking, scope: "AdGuard client \(config.clientIP). Saves the full custom-rule list while preserving \(existing.count) existing entries; use one editor at a time.", config: config, expectedRules: existing, proposedRules: next)
        case .piHole6:
            guard config.piHoleGroup >= 0 else { throw GuardianError.invalid("Pi-hole group ID must be nonnegative.") }
            if !blocking { throw GuardianError.unavailable("To preserve other groups' policy, Pi-hole removal must be reviewed in its dashboard. TV Guardian adds exact deny rules only.") }
            return DNSChangePreview(domain: domain, blocking: true, scope: "Pi-hole exact domain in group \(config.piHoleGroup). Every client assigned to that group is affected; subdomains need separate rules.", config: config)
        case .nextDNS:
            return DNSChangePreview(domain: domain, blocking: blocking, scope: "NextDNS profile \(config.profileID). All devices using this profile are affected. Removal only removes this denylist entry.", config: config)
        }
    }
    func apply(_ preview: DNSChangePreview) async throws -> String {
        let config = preview.config
        switch config.provider {
        case .adguardHome:
            let current = try await http.request(base: base(config), path: "/control/filtering/status", headers: basic(config))
            guard let expected = preview.expectedRules, let next = preview.proposedRules,
                  current["user_rules"] as? [String] == expected else { throw GuardianError.denied("AdGuard rules changed after preview. Refresh the preview before saving.") }
            _ = try await http.request(base: base(config), path: "/control/filtering/set_rules", method: "POST", headers: basic(config), body: ["rules": next])
            let check = try await http.request(base: base(config), path: "/control/filtering/status", headers: basic(config))
            guard check["user_rules"] as? [String] == next else { throw GuardianError.unavailable("AdGuard accepted the request, but rule read-back did not match. Review the provider dashboard.") }
        case .piHole6:
            let result = try await piHole(config, path: "/api/domains/deny/exact", method: "POST", body: ["domain": preview.domain, "comment": "TV Guardian", "enabled": true, "groups": [config.piHoleGroup]])
            guard let processed = result["processed"] as? [String: Any],
                  let errors = processed["errors"] as? [Any], errors.isEmpty,
                  let successes = processed["success"] as? [[String: Any]], successes.contains(where: { $0["item"] as? String == preview.domain }) else {
                throw GuardianError.unavailable("Pi-hole did not confirm the exact deny-rule change. An existing entry is not overwritten.")
            }
        case .nextDNS:
            let path = "/profiles/\(config.profileID)/denylist"
            let headers = ["X-Api-Key": try secret(config)]
            if preview.blocking {
                _ = try await http.request(base: base(config), path: path, method: "POST", headers: headers, body: ["id": preview.domain, "active": true])
            } else {
                _ = try await http.request(base: base(config), path: path + "/" + preview.domain, method: "DELETE", headers: headers)
            }
            let data = try await nextDNSDenylist(config)
            let active = data.contains { $0["id"] as? String == preview.domain && $0["active"] as? Bool == true }
            guard active == preview.blocking else { throw GuardianError.unavailable("NextDNS denylist read-back did not confirm the requested state.") }
        }
        return "Provider rule verified. TV traffic enforcement still requires correct DNS routing; this is not an app lock."
    }
    private func nextDNSDenylist(_ config: DNSConfiguration) async throws -> [[String: Any]] {
        var entries: [[String: Any]] = []
        var cursor: String?
        var visited = Set<String>()
        for _ in 0..<50 {
            let page = try await http.request(base: base(config), path: "/profiles/\(config.profileID)/denylist", headers: ["X-Api-Key": try secret(config)], query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
            guard let data = page["data"] as? [[String: Any]] else { throw GuardianError.protocolError("Unknown NextDNS denylist format.") }
            entries += data
            guard entries.count <= 10_000 else { throw GuardianError.unavailable("NextDNS read-back exceeds the bounded verification limit.") }
            let meta = page["meta"] as? [String: Any]
            let pagination = meta?["pagination"] as? [String: Any]
            guard let next = pagination?["cursor"] as? String, !next.isEmpty else { return entries }
            guard visited.insert(next).inserted else { throw GuardianError.protocolError("NextDNS repeated a pagination cursor.") }
            cursor = next
        }
        throw GuardianError.unavailable("NextDNS denylist exceeded the pagination limit. Verify the change in the provider dashboard.")
    }
    func queries(_ config: DNSConfiguration) async throws -> [DNSQuery] {
        switch config.provider {
        case .adguardHome:
            let data = try await http.request(base: base(config), path: "/control/querylog", headers: basic(config), query: [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "search", value: config.clientIP)])
            guard let rows = data["data"] as? [[String: Any]] else { throw GuardianError.protocolError("Unknown AdGuard query-log format.") }
            return rows.map { row in
                DNSQuery(domain: (row["question"] as? [String: Any])?["name"] as? String ?? "Unknown", client: row["client"] as? String ?? "Unknown", result: row["reason"] as? String ?? "Unknown", time: row["time"] as? String ?? "")
            }
        case .piHole6:
            let data = try await piHole(config, path: "/api/queries", query: [URLQueryItem(name: "length", value: "100"), URLQueryItem(name: "client", value: config.clientIP.isEmpty ? nil : config.clientIP)])
            guard let rows = data["queries"] as? [[String: Any]] else { throw GuardianError.protocolError("Unknown Pi-hole v6 query format.") }
            return rows.map { row in
                DNSQuery(domain: row["domain"] as? String ?? "Unknown", client: (row["client"] as? [String: Any])?["ip"] as? String ?? "Unknown", result: row["status"] as? String ?? "Unknown", time: (row["time"] as? Double).map { Date(timeIntervalSince1970: $0).formatted() } ?? "")
            }
        case .nextDNS:
            let data = try await http.request(base: base(config), path: "/profiles/\(config.profileID)/logs", headers: ["X-Api-Key": try secret(config)], query: [URLQueryItem(name: "limit", value: "100")])
            guard let rows = data["data"] as? [[String: Any]] else { throw GuardianError.protocolError("Unknown NextDNS query format.") }
            return rows.map { row in
                DNSQuery(domain: row["domain"] as? String ?? "Unknown", client: (row["device"] as? [String: Any])?["name"] as? String ?? row["clientIp"] as? String ?? "Unidentified", result: row["status"] as? String ?? "Unknown", time: row["timestamp"] as? String ?? "")
            }
        }
    }
}
