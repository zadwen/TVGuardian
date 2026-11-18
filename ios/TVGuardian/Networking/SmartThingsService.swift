import Foundation

struct SmartThingsDevice: Identifiable, Decodable {
    var deviceId: String
    var label: String?
    var name: String?
    var components: [Component]?
    var id: String { deviceId }
    struct Component: Decodable { var id: String; var capabilities: [Capability] }
    struct Capability: Decodable { var id: String; var version: Int }
    func supports(_ capability: String) -> Bool { components?.first(where: { $0.id == "main" })?.capabilities.contains(where: { $0.id == capability && $0.version == 1 }) == true }
}

@MainActor final class SmartThingsService {
    private let http = SecureHTTPClient()
    private let base = URL(string: "https://api.smartthings.com")!
    private func headers() throws -> [String: String] {
        guard let token = try KeychainStore.string("smartthings.accessToken"), !token.isEmpty else { throw GuardianError.denied("Save an authorized SmartThings access token first. Development PATs expire.") }
        return ["Authorization": "Bearer \(token)"]
    }
    func devices() async throws -> [SmartThingsDevice] {
        var path = "/v1/devices"
        var query: [URLQueryItem] = []
        var results: [SmartThingsDevice] = []
        var visited = Set<String>()
        for _ in 0..<20 {
            let response = try await http.request(base: base, path: path, headers: headers(), query: query)
            guard let items = response["items"] as? [[String: Any]] else { throw GuardianError.protocolError("SmartThings device list is malformed.") }
            let bytes = try JSONSerialization.data(withJSONObject: items)
            results += try JSONDecoder().decode([SmartThingsDevice].self, from: bytes)
            guard let links = response["_links"] as? [String: Any], let next = links["next"] as? [String: Any], let href = next["href"] as? String else { return results }
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL, url.scheme == "https", url.host == base.host,
                  url.path == "/v1/devices", url.user == nil, url.password == nil, visited.insert(url.absoluteString).inserted else { throw GuardianError.protocolError("Unsafe or repeated SmartThings pagination link.") }
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            path = parts.path; query = parts.queryItems ?? []
        }
        throw GuardianError.unavailable("SmartThings device list exceeded the pagination limit.")
    }
    func status(_ device: SmartThingsDevice) async throws -> String {
        let id = try Validation.identifier(device.id)
        let data = try await http.request(base: base, path: "/v1/devices/\(id)/status", headers: headers())
        return String(data: try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? ""
    }
    func supportedInputs(_ device: SmartThingsDevice) async throws -> [String] {
        guard device.supports("mediaInputSource") else { return [] }
        let id = try Validation.identifier(device.id)
        let data = try await http.request(base: base, path: "/v1/devices/\(id)/components/main/capabilities/mediaInputSource/status", headers: headers())
        let attribute = data["supportedInputSources"] as? [String: Any]
        return attribute?["value"] as? [String] ?? []
    }
    func power(_ on: Bool, device: SmartThingsDevice) async throws {
        try await command(capability: "switch", name: on ? "on" : "off", arguments: [], device: device)
    }
    func volume(_ level: Int, device: SmartThingsDevice) async throws {
        guard (0...100).contains(level) else { throw GuardianError.invalid("Volume must be from 0 to 100.") }
        try await command(capability: "audioVolume", name: "setVolume", arguments: [level], device: device)
    }
    func input(_ source: String, device: SmartThingsDevice) async throws {
        let supported = try await supportedInputs(device)
        guard supported.contains(source) else { throw GuardianError.denied("This input was not reported by the selected device's mediaInputSource capability.") }
        try await command(capability: "mediaInputSource", name: "setInputSource", arguments: [source], device: device)
    }
    private func command(capability: String, name: String, arguments: [Any], device: SmartThingsDevice) async throws {
        guard device.supports(capability) else { throw GuardianError.unavailable("This device does not advertise \(capability) v1 on main.") }
        let id = try Validation.identifier(device.id)
        let result = try await http.request(base: base, path: "/v1/devices/\(id)/commands", method: "POST", headers: headers(), body: ["commands": [["component": "main", "capability": capability, "command": name, "arguments": arguments] as [String: Any]]])
        guard let results = result["results"] as? [[String: Any]], !results.isEmpty,
              results.allSatisfy({ ["ACCEPTED", "COMPLETED"].contains($0["status"] as? String ?? "") }) else {
            throw GuardianError.unavailable("SmartThings did not acknowledge the command. Check device status.")
        }
    }
}
