import Foundation

struct CompanionReport: Decodable {
    var companionID: String
    var name: String
    var receivedAt: String
    var stale: Bool
    var snapshot: Snapshot?
    struct Snapshot: Decodable {
        var apps: [App]
        var errors: [String]
        var inventoryStatus: String
        var complete: Bool
        struct App: Decodable { var id: String; var name: String; var packageID: String?; var iconPath: String? }
    }
}
struct CompanionPairing: Decodable { var code: String; var expiresAt: String }

@MainActor final class CompanionService {
    private let http = SecureHTTPClient()
    func storeParentToken(_ value: String, base: String) throws {
        guard (40...256).contains(value.count), value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw GuardianError.invalid("Use the generated base64url parent bridge token.") }
        let account = try KeychainStore.scopedAccount("bridge.parentToken", origin: Validation.httpsBase(base))
        try KeychainStore.writeString(value, account: account)
    }
    private func headers(base: String) throws -> [String: String] {
        let account = try KeychainStore.scopedAccount("bridge.parentToken", origin: Validation.httpsBase(base))
        guard let token = try KeychainStore.string(account), (40...256).contains(token.count),
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw GuardianError.denied("Save the bridge's generated parent access token in Keychain.") }
        return ["Authorization": "Bearer \(token)"]
    }
    func openPairing(base: String) async throws -> CompanionPairing {
        let result = try await http.request(base: Validation.httpsBase(base), path: "/v1/pairing/open", method: "POST", headers: headers(base: base), body: [:])
        return try JSONDecoder().decode(CompanionPairing.self, from: JSONSerialization.data(withJSONObject: result))
    }
    func reports(base: String) async throws -> [CompanionReport] {
        let result = try await http.request(base: Validation.httpsBase(base), path: "/v1/companions", headers: headers(base: base))
        guard let items = result["items"] as? [[String: Any]] else { throw GuardianError.protocolError("The bridge returned an unknown inventory format.") }
        return try JSONDecoder().decode([CompanionReport].self, from: JSONSerialization.data(withJSONObject: items))
    }
    func revoke(base: String, id: String) async throws {
        _ = try await http.request(base: Validation.httpsBase(base), path: "/v1/companions/\(try Validation.identifier(id))", method: "DELETE", headers: headers(base: base))
    }
}
