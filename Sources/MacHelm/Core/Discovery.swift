import Foundation
import Network

/// Finds Macs on the local network that advertise SSH (Remote Login) over Bonjour.
@MainActor @Observable
final class Discovery {
    struct Found: Identifiable, Hashable {
        var id: String
        var name: String
        var host: String
        var port: Int
    }

    var found: [Found] = []
    var scanning = false

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolvers: [String: NWConnection] = [:]

    func start() {
        stop()
        scanning = true
        let b = NWBrowser(for: .bonjour(type: "_ssh._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results) }
        }
        b.start(queue: .main)
        browser = b
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.scanning = false }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers = [:]
        scanning = false
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            let key = name
            guard resolvers[key] == nil else { continue }
            let tcp = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcp)
            (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
            let conn = NWConnection(to: r.endpoint, using: params)
            conn.stateUpdateHandler = { [weak self] state in
                guard case .ready = state else { return }
                if case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                    let h = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                    Task { @MainActor in
                        guard let self else { return }
                        let f = Found(id: key, name: name, host: h, port: Int(port.rawValue))
                        if !self.found.contains(where: { $0.id == key }) { self.found.append(f) }
                    }
                }
                conn.cancel()
            }
            conn.start(queue: .main)
            resolvers[key] = conn
        }
    }
}
