import Combine
import Darwin
import Foundation
import Network
import Security

struct DiskRoute: Hashable, Codable {
    var address: String?
    var port: UInt16 = 0

    static let internet = DiskRoute(address: nil)  // Existing sessions and the simulator fixture.
    static let sessionPrefix = (Bundle.main.bundleIdentifier ?? "ru.atma.phonedisk") + ".v2."
    static let backgroundPort = 18117
    static let tailnet: DiskRoute? = {
        guard let address = Bundle.main.object(forInfoDictionaryKey: "PhoneDiskTailnetIPv4") as? String else {
            return nil
        }
        return tailnetRoute(address, port: 18113)
    }()

    var identifier: String { Self.sessionPrefix + (address.map { $0 + "." + String(port) } ?? "internet") }
    var backgroundIdentifier: String { identifier + ".background" }
    var isTailnet: Bool { address.map { Self.tailnetRoute($0, port: port) != nil } ?? false }
    var isLocal: Bool { address != nil && !isTailnet }
    var label: String { isLocal ? "Домашняя сеть" : isTailnet ? "Tailscale" : "Интернет" }

    func backgroundURL(_ url: URL) -> URL {
        guard let address, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = address
        components.port = Self.backgroundPort
        return components.url ?? url
    }

    func acceptsBackgroundURL(_ url: URL?) -> Bool {
        guard let url, url.user == nil, url.password == nil else { return false }
        let base = backgroundURL(Transfers.base)
        return url.scheme == base.scheme && url.host == base.host && (url.port ?? 443) == (base.port ?? 443)
    }

    // The embedded web interface retains its existing origin and login cookies.
    // Native transfer requests connect directly to the machine's address.
    var proxy: [ProxyConfiguration] {
        guard let address, let port = NWEndpoint.Port(rawValue: port), let host = IPv4Address(address) else { return [] }
        var configuration = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .ipv4(host), port: port))
        configuration.matchDomains = ["files.rynpro.ru"]
        configuration.allowFailover = false
        return [configuration]
    }

    func evaluate(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let address else { return (.performDefaultHandling, nil) }
        guard challenge.protectionSpace.host == address,
              challenge.protectionSpace.port == Self.backgroundPort,
              let trust = challenge.protectionSpace.serverTrust, let host = Transfers.base.host,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    private static func octets(_ address: String, port: UInt16) -> [UInt8]? {
        guard port == 18113, IPv4Address(address) != nil else { return nil }
        let numbers = address.split(separator: ".").compactMap { UInt8($0) }
        return numbers.count == 4 ? numbers : nil
    }

    static func local(_ address: String, port: UInt16) -> DiskRoute? {
        guard let numbers = octets(address, port: port),
              numbers[0] == 10 || (numbers[0] == 172 && (16...31).contains(numbers[1])) ||
              (numbers[0] == 192 && numbers[1] == 168) else { return nil }
        return DiskRoute(address: address, port: port)
    }

    private static func tailnetRoute(_ address: String, port: UInt16) -> DiskRoute? {
        guard let numbers = octets(address, port: port),
              numbers[0] == 100, (64...127).contains(numbers[1]) else { return nil }
        return DiskRoute(address: address, port: port)
    }

    static func restore(_ identifier: String) -> DiskRoute? {
        guard identifier.hasPrefix(sessionPrefix) else { return nil }
        var value = String(identifier.dropFirst(sessionPrefix.count))
        if value.hasSuffix(".background") { value.removeLast(".background".count) }
        if value == "internet" { return .internet }
        guard let boundary = value.lastIndex(of: "."),
              let port = UInt16(value[value.index(after: boundary)...]) else { return nil }
        let address = String(value[..<boundary])
        return local(address, port: port) ?? tailnetRoute(address, port: port)
    }
}

struct DiskCapabilities: Decodable {
    var version: Int
    var serverId: String
    var lan: Bool
    var autoFinishUploads: Bool?
}

final class DiskRoutes: NSObject, ObservableObject, URLSessionTaskDelegate {
    static let shared = DiskRoutes()
    @Published private(set) var selected: DiskRoute?
    private var browser: NWBrowser?
    private var monitor: NWPathMonitor?
    private var wifiAvailable: Bool?
    private var wifiInterfaces = Set<String>()
    private var candidates = Set<DiskRoute>()
    private var controlSessions = [String: URLSession]()
    private var selection: Task<DiskRoute?, Never>?
    private var recheck: Task<Void, Never>?
    private var generation = 0
    private let clock = ContinuousClock()
    private var verifiedAt: ContinuousClock.Instant?
    private let serverKey = "phone-disk-server-identity"
    private let localKey = "phone-disk-last-local-route"

    @MainActor func start() {
        guard monitor == nil, Transfers.base.host != "127.0.0.1" else { return }
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            let interfaces = Set(path.availableInterfaces.filter { $0.type == .wifi }.map(\.name))
            Task { @MainActor in
                guard let self else { return }
                self.wifiAvailable = available
                self.wifiInterfaces = interfaces
                self.refresh()
            }
        }
        self.monitor = monitor
        monitor.start(queue: .global(qos: .utility))

        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_phonedisk._tcp", domain: "local."), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovered = Set(results.compactMap { result -> DiskRoute? in
                guard case .bonjour(let txt) = result.metadata, let address = txt.dictionary["address"],
                      let value = txt.dictionary["port"], let port = UInt16(value) else { return nil }
                return DiskRoute.local(address, port: port)
            })
            Task { @MainActor in
                guard let self, self.candidates != discovered else { return }
                self.candidates = discovered
                self.refresh()
            }
        }
        self.browser = browser
        browser.start(queue: .main)
        _ = select()
    }

    @MainActor func resolve() async throws -> DiskRoute {
        if Transfers.base.host == "127.0.0.1" { return .internet }
        start()
        while true {
            try Task.checkCancellation()
            if selection == nil, let selected, let verifiedAt,
               verifiedAt.duration(to: clock.now) < .seconds(selected.isLocal ? 10 : 3) {
                return selected
            }
            let revision = generation
            let route = await select().value
            guard revision == generation else { continue }
            try Task.checkCancellation()
            guard let route else { throw URLError(.notConnectedToInternet) }
            return route
        }
    }

    @MainActor func refresh() {
        guard monitor != nil else { return }
        generation += 1
        verifiedAt = nil
        selection?.cancel()
        selection = nil
        _ = select()
    }

    @MainActor private func select() -> Task<DiskRoute?, Never> {
        if let selection { return selection }
        recheck?.cancel()
        recheck = nil
        let revision = generation
        let task = Task<DiskRoute?, Never> { @MainActor in
            let route = await reachableRoute()
            guard !Task.isCancelled, generation == revision else { return nil }
            verifiedAt = route == nil ? nil : clock.now
            selection = nil
            if selected != route { selected = route }
            // Retry in place after a PC restart or late Bonjour reply.
            if route == nil || (route?.isTailnet == true && wifiAvailable != false) {
                recheck = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    self?.refresh()
                }
            }
            return route
        }
        selection = task
        return task
    }

    private func onLink(_ route: DiskRoute, _ networks: [(address: UInt32, mask: UInt32)]) -> Bool {
        guard let address = route.address, let ip = IPv4Address(address) else { return false }
        let value = ip.rawValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return networks.contains { (value & $0.mask) == ($0.address & $0.mask) }
    }

    @MainActor private func wifiNetworks() -> [(address: UInt32, mask: UInt32)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }
        return sequence(first: head, next: { $0.pointee.ifa_next }).compactMap { entry in
            let interface = entry.pointee
            guard wifiInterfaces.contains(String(cString: interface.ifa_name)),
                  let address = interface.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = interface.ifa_netmask else { return nil }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            return mask != 0 ? (ip, mask) : nil
        }
    }

    @MainActor private func reachableRoute() async -> DiskRoute? {
        var local: [DiskRoute] = []
        if wifiAvailable != false {
            if candidates.isEmpty {
                // Give Bonjour time to find a new address after joining Wi-Fi.
                try? await Task.sleep(for: .milliseconds(800))
            }
            let networks = wifiNetworks()
            let saved = UserDefaults.standard.string(forKey: localKey).flatMap(DiskRoute.restore)
            local = candidates.filter { onLink($0, networks) }.sorted { $0.identifier < $1.identifier }
            if let saved, saved.isLocal, onLink(saved, networks) {
                if let index = local.firstIndex(of: saved) { local.swapAt(0, index) }
                else { local.append(saved) }
            }
        }
        let route = await Self.firstReachable(local: Array(local.prefix(3)), fallback: DiskRoute.tailnet) { route in
            (try? await self.capabilities(route)) != nil
        }
        if let route, route.isLocal { UserDefaults.standard.set(route.identifier, forKey: localKey) }
        return route
    }

    @MainActor static func firstReachable(local: [DiskRoute], fallback: DiskRoute?,
                                          probe: (DiskRoute) async -> Bool) async -> DiskRoute? {
        for route in local + (fallback.map { [$0] } ?? []) {
            guard !Task.isCancelled else { return nil }
            if await probe(route), !Task.isCancelled { return route }
        }
        return nil
    }

    @MainActor func data(_ request: URLRequest, route hint: DiskRoute? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, Transfers.sameHost(url) else { throw DiskFailure.rejected }
        let route: DiskRoute
        if let hint { route = hint }
        else { route = try await resolve() }
        let direct = url.path.hasPrefix("/api/v2/")
        var routed = request
        if direct { routed.url = route.backgroundURL(url) }

        let key = direct ? route.backgroundIdentifier : route.identifier
        let session: URLSession
        if let saved = controlSessions[key] { session = saved }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.allowsCellularAccess = !route.isLocal
            configuration.proxyConfigurations = direct ? [] : route.proxy
            if direct { configuration.connectionProxyDictionary = [:] }
            configuration.httpShouldSetCookies = false
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
            controlSessions[key] = session
        }
        let (data, response) = try await session.data(for: routed)
        guard let reply = response as? HTTPURLResponse,
              direct ? route.acceptsBackgroundURL(reply.url) : Transfers.sameHost(reply.url) else { throw DiskFailure.rejected }
        return (data, reply)
    }

    @MainActor func capabilities(_ route: DiskRoute) async throws -> DiskCapabilities? {
        let url = Transfers.address("/api/v2/capabilities")
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        let (data, response) = try await self.data(request, route: route)
        if response.statusCode == 404, route == .internet { return nil }
        guard response.statusCode == 200, let result = try? JSONDecoder().decode(DiskCapabilities.self, from: data),
              result.version == 2, result.serverId.count == 32, result.lan == route.isLocal else { throw DiskFailure.rejected }
        let defaults = UserDefaults.standard
        if let known = defaults.string(forKey: serverKey), known != result.serverId { throw DiskFailure.rejected }
        defaults.set(result.serverId, forKey: serverKey)
        return result
    }

    @MainActor func failed(_ route: DiskRoute) {
        if selected == route { refresh() }
    }

    // Delegate deliveries use the main queue, together with the session cache.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let key = controlSessions.first(where: { $0.value === session })?.key,
              key.hasSuffix(".background"), let route = DiskRoute.restore(key) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let (disposition, credential) = route.evaluate(challenge)
        completionHandler(disposition, credential)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
