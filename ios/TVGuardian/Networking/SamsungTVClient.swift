import Foundation

struct TVMetadata {
    var name: String
    var model: String
    var firmware: String?
    var identity: String?
}

@MainActor final class SamsungTVClient {
    private var transport: PinnedTVSession?
    private var socket: URLSessionWebSocketTask?
    private(set) var connectedTVID: UUID?
    var isConnected: Bool { connectedTVID != nil && socket?.state == .running }
    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        transport?.invalidate(); transport = nil; connectedTVID = nil
    }
    func inspect(_ tv: TVRecord) async throws -> TVMetadata {
        let client = try PinnedTVSession(host: tv.host, expectedFingerprint: KeychainStore.string("tv.\(tv.id).pin"))
        defer { client.invalidate() }
        let json = try await client.request("/api/v2/")
        guard let device = json["device"] as? [String: Any] else { throw GuardianError.protocolError("The endpoint did not identify a Samsung TV.") }
        guard let model = device["modelName"] as? String ?? device["model"] as? String,
              !model.isEmpty else { throw GuardianError.protocolError("TV model information was absent.") }
        return TVMetadata(name: device["name"] as? String ?? tv.name, model: model,
                          firmware: device["firmwareVersion"] as? String,
                          identity: device["duid"] as? String ?? json["id"] as? String)
    }
    func connect(_ tv: TVRecord, allowPairing: Bool) async throws {
        disconnect()
        let pin = try KeychainStore.string("tv.\(tv.id).pin")
        guard pin != nil else { _ = try await inspect(tv); throw GuardianError.unavailable("Review the TV certificate first.") }
        let token = try KeychainStore.string("tv.\(tv.id).token")
        guard token != nil || allowPairing else { throw GuardianError.denied("Pairing requires a parent to approve the prompt on the TV.") }
        let client = try PinnedTVSession(host: tv.host, expectedFingerprint: pin)
        transport = client
        var components = URLComponents(); components.scheme = "wss"; components.host = tv.host; components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        components.queryItems = [URLQueryItem(name: "name", value: Data("TV Guardian".utf8).base64EncodedString())]
        if let token { components.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        let task = client.session.webSocketTask(with: components.url!)
        socket = task; task.resume()
        do {
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                let message = try await nextMessage(timeout: min(45, deadline.timeIntervalSinceNow))
                switch message["event"] as? String {
                case "ms.channel.connect":
                    var credentialAvailable = token != nil
                    if let data = message["data"] as? [String: Any], let newToken = data["token"] as? String, !newToken.isEmpty {
                        try KeychainStore.writeString(newToken, account: "tv.\(tv.id).token")
                        credentialAvailable = true
                    }
                    guard credentialAvailable else { throw GuardianError.denied("The TV connected without issuing a pairing credential. This build requires authenticated token pairing and will not fall back to an unauthenticated channel.") }
                    connectedTVID = tv.id; return
                case "ms.channel.unauthorized": throw GuardianError.denied("The TV denied pairing. Review Device Connect Manager on the TV and pair again.")
                case "ms.error": throw GuardianError.protocolError("The TV rejected the control channel.")
                default: continue
                }
            }
            throw GuardianError.unavailable("TV pairing timed out. Turn on the TV and approve its connection prompt.")
        } catch { let mapped = client.translated(error); disconnect(); throw mapped }
    }
    private func nextMessage(timeout: TimeInterval) async throws -> [String: Any] {
        guard let socket else { throw GuardianError.unavailable("No TV connection.") }
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let message = try await socket.receive()
                switch message { case .data(let data): return data; case .string(let text): return Data(text.utf8); @unknown default: throw GuardianError.protocolError("Unknown WebSocket frame.") }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                socket.cancel(with: .goingAway, reason: nil)
                throw GuardianError.unavailable("TV response timed out. Support remains unverified.")
            }
            defer { group.cancelAll() }
            guard let data = try await group.next(), data.count <= 2_000_000,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GuardianError.protocolError("Invalid or oversized TV event.")
            }
            return json
        }
    }
    private func send(_ json: [String: Any]) async throws {
        try Task.checkCancellation()
        guard let socket, connectedTVID != nil else { throw GuardianError.unavailable("Connect to the TV first.") }
        let data = try JSONSerialization.data(withJSONObject: json)
        guard let text = String(data: data, encoding: .utf8) else { throw GuardianError.protocolError("Cannot encode TV request.") }
        do { try await socket.send(.string(text)) } catch { disconnect(); throw error }
    }
    func installedApplications() async throws -> [TVApplication] {
        try await send(["method": "ms.channel.emit", "params": ["event": "ed.installedApp.get", "to": "host"]])
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            let event = try await nextMessage(timeout: deadline.timeIntervalSinceNow)
            if event["event"] as? String == "ms.error" { throw GuardianError.protocolError("TV declined installed-app discovery.") }
            guard event["event"] as? String == "ed.installedApp.get" else { continue }
            return try SamsungProtocol.applications(from: event)
        }
        throw GuardianError.unavailable("The TV did not return an app inventory. Try the foreground companion.")
    }
    func launch(_ app: TVApplication) async throws {
        guard let launchID = app.launchID else { throw GuardianError.unavailable("This Tizen identifier has no verified Samsung launch ID. Refresh the TV's WebSocket app list; identifiers are not guessed.") }
        let id = try Validation.identifier(launchID)
        try await send(["method": "ms.channel.emit", "params": ["event": "ed.apps.launch", "to": "host",
            "data": ["action_type": app.appType == 2 ? "DEEP_LINK" : "NATIVE_LAUNCH", "appId": id, "metaTag": ""]]])
    }
    func status(_ app: TVApplication) async throws -> Bool {
        guard let transport, let launchID = app.launchID else { throw GuardianError.unavailable("No reported Samsung REST app ID.") }
        let id = try Validation.identifier(launchID)
        let result = try await transport.request("/api/v2/applications/\(id)")
        guard let running = result["running"] as? Bool else { throw GuardianError.protocolError("The TV did not report an app running state. Close remains unverified.") }
        return running
    }
    /// DELETE is upstream's close operation. It is never a package deletion.
    func close(_ app: TVApplication) async throws -> Bool {
        guard let transport, let launchID = app.launchID else { throw GuardianError.unavailable("No verified REST app identifier.") }
        guard try await status(app) else { return false }
        let id = try Validation.identifier(launchID)
        _ = try await transport.request("/api/v2/applications/\(id)", method: "DELETE")
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 700_000_000)
            let running = try await status(app)
            if !running { return true }
        }
        throw GuardianError.unavailable("Close was requested, but a stopped state was not observed. No successful close is recorded.")
    }
    func key(_ key: RemoteKey) async throws {
        try await send(["method": "ms.remote.control", "params": ["Cmd": "Click", "DataOfCmd": key.rawValue,
            "Option": "false", "TypeOfRemote": "SendRemoteKey"]])
    }
    func ping() async throws {
        guard let socket else { throw GuardianError.unavailable("No connection.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
    }
    func icon(_ app: TVApplication) async throws -> Data? {
        guard let url = app.iconURL, let transport else { return nil }
        return try await transport.image(at: url)
    }
}

enum RemoteKey: String, CaseIterable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT", enter = "KEY_ENTER"
    case home = "KEY_HOME", back = "KEY_RETURN", menu = "KEY_MENU", source = "KEY_SOURCE"
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case play = "KEY_PLAY", pause = "KEY_PAUSE", powerOff = "KEY_POWEROFF"
}
