import Foundation
import Network
import Combine

struct DiscoveredTV: Identifiable {
    var id: String { host }
    var name: String
    var host: String
    var source: String
}

@MainActor final class DiscoveryService: ObservableObject {
    @Published var devices: [DiscoveredTV] = []
    @Published var status = "Discovery has not started."
    private var browsers: [NWBrowser] = []
    private var resolvers: [NWConnection] = []
    private var generation = UUID()
    func start() {
        stop(); let current = generation; devices = []
        status = "Browsing Bonjour. Some Samsung TVs need a manual IP connection."
        for type in ["_samsungmsf._tcp", "_airplay._tcp"] {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    if case .waiting(let error) = state { self.status = "Discovery is waiting: \(error.localizedDescription). Check Local Network permission." }
                    if case .failed = state { self.status = "Bonjour unavailable. Use the TV's private IP and check iOS Local Network permission." }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    for result in results { self.resolve(result.endpoint, type: type, generation: current) }
                }
            }
            browsers.append(browser); browser.start(queue: .global(qos: .utility))
        }
    }
    private func resolve(_ endpoint: NWEndpoint, type: String, generation: UUID) {
        guard resolvers.count < 64, case .service(let name, _, _, _) = endpoint else { return }
        // AirPlay also advertises non-Samsung devices. Never identify one as a
        // Samsung TV until its separately pinned metadata response is inspected.
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolvers.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .ready = state, let connection else { return }
            let remote = connection.currentPath?.remoteEndpoint
            Task { @MainActor in
                defer { connection.cancel() }
                guard let self, self.generation == generation, let remote,
                      case .hostPort(let host, _) = remote, Validation.privateIPv4(host.debugDescription) else { return }
                let address = host.debugDescription
                if !self.devices.contains(where: { $0.host == address }) {
                    self.devices.append(DiscoveredTV(name: name, host: address, source: type == "_airplay._tcp" ? "AirPlay candidate; verify Samsung identity" : "Samsung Bonjour candidate"))
                }
            }
        }
        connection.start(queue: .global(qos: .utility))
        Task { try? await Task.sleep(nanoseconds: 5_000_000_000); connection.cancel() }
    }
    func stop() {
        generation = UUID(); browsers.forEach { $0.cancel() }; browsers = []
        resolvers.forEach { $0.cancel() }; resolvers = []
    }
}
