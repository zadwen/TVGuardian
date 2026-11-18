import Foundation

enum SamsungProtocol {
    static func applications(from event: [String: Any]) throws -> [TVApplication] {
        guard event["event"] as? String == "ed.installedApp.get" else { throw GuardianError.protocolError("This event is not an installed-app response.") }
        var data = event["data"]
        if let string = data as? String, let bytes = string.data(using: .utf8) { data = try JSONSerialization.jsonObject(with: bytes) }
        guard let envelope = data as? [String: Any], let apps = envelope["data"] as? [[String: Any]], apps.count <= 2000 else {
            throw GuardianError.protocolError("Unrecognized installed-app response. No empty inventory was substituted.")
        }
        var seen = Set<String>()
        return try apps.map { app in
            guard let rawID = app["appId"] as? String else { throw GuardianError.protocolError("A TV app entry did not contain a launch ID.") }
            let id = try Validation.identifier(rawID)
            guard seen.insert(id).inserted else { throw GuardianError.protocolError("Duplicate app IDs in the TV response.") }
            return TVApplication(id: id, name: app["name"] as? String ?? id, origin: .samsungWebSocket, launchID: id,
                                 iconURL: app["icon"] as? String, appType: app["app_type"] as? Int)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
