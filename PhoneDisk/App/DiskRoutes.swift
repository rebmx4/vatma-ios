import Combine
import Darwin
import Foundation
import Network
import Security

struct DiskRoute: Hashable, Codable {
    var address: String?
    var port: UInt16 = 0
    var companionID: String?

    static let internet = DiskRoute(address: nil)  // Existing sessions and the simulator fixture.
    static let sessionPrefix = (Bundle.main.bundleIdentifier ?? "ru.atma.phonedisk") + ".v2."
    static let backgroundPort = 18117
    static let tailnet: DiskRoute? = {
        guard let address = Bundle.main.object(forInfoDictionaryKey: "PhoneDiskTailnetIPv4") as? String else {
            return nil
        }
        return tailnetRoute(address, port: 18113)
    }()

    var identifier: String {
        let peer = companionID.map { "pc." + $0 + "." } ?? ""
        return Self.sessionPrefix + peer + (address.map { $0 + "." + String(port) } ?? "internet")
    }
    var backgroundIdentifier: String { identifier + ".background" }
    var isTailnet: Bool {
        guard let address, let numbers = Self.octets(address) else { return false }
        return numbers[0] == 100 && (64...127).contains(numbers[1])
    }
    var isLocal: Bool { address != nil && !isTailnet }
    var label: String { isLocal ? "Домашняя сеть" : isTailnet ? "Tailscale" : "Интернет" }

    var webOrigin: URL? {
        guard companionID != nil, let address else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = address
        components.port = Int(port)
        components.path = "/"
        return components.url
    }

    func backgroundURL(_ url: URL) -> URL {
        guard let address, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = address
        components.port = companionID == nil ? Self.backgroundPort : Int(port)
        return components.url ?? url
    }

    func acceptsBackgroundURL(_ url: URL?) -> Bool {
        guard let url, url.user == nil, url.password == nil else { return false }
        let base = webOrigin ?? backgroundURL(Transfers.base)
        return url.scheme == base.scheme && url.host == base.host && (url.port ?? 443) == (base.port ?? 443)
    }

    // The embedded web interface retains its existing origin and login cookies.
    // Native transfer requests connect directly to the machine's address.
    var proxy: [ProxyConfiguration] {
        guard companionID == nil, let address, let port = NWEndpoint.Port(rawValue: port), let host = IPv4Address(address) else { return [] }
        var configuration = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .ipv4(host), port: port))
        configuration.matchDomains = ["files.rynpro.ru"]
        configuration.allowFailover = false
        return [configuration]
    }

    func evaluate(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let companionID {
            guard let paired = PairedComputer.load(), paired.id == companionID, paired.port == port else {
                return (.cancelAuthenticationChallenge, nil)
            }
            return ComputerTrust.verify(challenge, route: self, fingerprint: paired.fingerprint)
        }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let address else { return (.performDefaultHandling, nil) }
        guard challenge.protectionSpace.host == address,
              challenge.protectionSpace.port == Self.backgroundPort,
              let trust = challenge.protectionSpace.serverTrust, let host = Transfers.base.host,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    private static func octets(_ address: String) -> [UInt8]? {
        guard IPv4Address(address) != nil else { return nil }
        let numbers = address.split(separator: ".").compactMap { UInt8($0) }
        return numbers.count == 4 ? numbers : nil
    }

    private static func isLocal(_ numbers: [UInt8]) -> Bool {
        numbers[0] == 10 || (numbers[0] == 172 && (16...31).contains(numbers[1])) ||
            (numbers[0] == 192 && numbers[1] == 168)
    }

    static func local(_ address: String, port: UInt16) -> DiskRoute? {
        guard port == 18113, let numbers = octets(address), isLocal(numbers) else { return nil }
        return DiskRoute(address: address, port: port)
    }

    private static func tailnetRoute(_ address: String, port: UInt16) -> DiskRoute? {
        guard port == 18113, let numbers = octets(address),
              numbers[0] == 100, (64...127).contains(numbers[1]) else { return nil }
        return DiskRoute(address: address, port: port)
    }

    static func companion(id: String, host: String, port: UInt16) -> DiskRoute? {
        guard PairInvitation.validID(id), port >= 1024, let numbers = octets(host),
              isLocal(numbers) || (numbers[0] == 100 && (64...127).contains(numbers[1]))
        else { return nil }
        return DiskRoute(address: host, port: port, companionID: id)
    }

    static func restore(_ identifier: String) -> DiskRoute? {
        guard identifier.hasPrefix(sessionPrefix) else { return nil }
        var value = String(identifier.dropFirst(sessionPrefix.count))
        if value.hasSuffix(".background") { value.removeLast(".background".count) }
        if value == "internet" { return .internet }
        if value.hasPrefix("pc.") {
            let components = value.split(separator: ".")
            guard components.count == 7, let port = UInt16(components[6]) else { return nil }
            return companion(id: String(components[1]), host: components[2...5].joined(separator: "."), port: port)
        }
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

    @MainActor func start(discovering: Bool = false) {
        guard monitor == nil, Transfers.base.host != "127.0.0.1" else { return }
        guard discovering || PairedComputer.load() != nil || PairedComputer.hasLegacyComputer else { return }
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
                if let id = txt.dictionary["id"] {
                    guard let result = DiskRoute.companion(id: id, host: address, port: port), result.isLocal else { return nil }
                    return result
                }
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

    @MainActor func connectionChanged() {
        controlSessions.values.forEach { $0.invalidateAndCancel() }
        controlSessions.removeAll()
        start()
        refresh()
    }

    @MainActor func routesForPairing(_ invitation: PairInvitation) async -> [DiskRoute] {
        start(discovering: true)
        if wifiInterfaces.isEmpty || !candidates.contains(where: { $0.companionID == invitation.id }) {
            try? await Task.sleep(for: .milliseconds(900))
        }
        let networks = wifiNetworks()
        let found = candidates.filter { $0.companionID == invitation.id && $0.port == invitation.port && onLink($0, networks) }
            .sorted { $0.identifier < $1.identifier }
        var routes = Array(found.prefix(3))
        if let route = DiskRoute.companion(id: invitation.id, host: invitation.host, port: invitation.port),
           onLink(route, networks), !routes.contains(route) {
            routes.append(route)
        }
        return routes
    }

    @MainActor func resolve() async throws -> DiskRoute {
        if Transfers.base.host == "127.0.0.1" { return .internet }
        guard PairedComputer.load() != nil || PairedComputer.hasLegacyComputer else { throw DiskFailure.signIn }
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
            if (PairedComputer.load() != nil || PairedComputer.hasLegacyComputer) &&
                (route == nil || (route?.isTailnet == true && wifiAvailable != false)) {
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
        let paired = PairedComputer.load()
        guard paired != nil || PairedComputer.hasLegacyComputer else { return nil }
        var local: [DiskRoute] = []
        if wifiAvailable != false {
            if !candidates.contains(where: { $0.companionID == paired?.id }) {
                // Give Bonjour time to find a new address after joining Wi-Fi.
                try? await Task.sleep(for: .milliseconds(1200))
            }
            let networks = wifiNetworks()
            let saved = UserDefaults.standard.string(forKey: localKey).flatMap(DiskRoute.restore)
            let preferred = saved?.companionID == paired?.id ? saved : paired?.preferredLocal
            local = candidates.filter { $0.companionID == paired?.id && onLink($0, networks) }
                .sorted { $0.identifier < $1.identifier }
            if let preferred, preferred.isLocal, onLink(preferred, networks) {
                if let index = local.firstIndex(of: preferred) { local.swapAt(0, index) }
                else { local.insert(preferred, at: 0) }
            }
        }
        let fallback = paired == nil ? DiskRoute.tailnet : paired?.fallback
        let route = await Self.firstReachable(local: Array(local.prefix(3)), fallback: fallback) { route in
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
        guard route.companionID == PairedComputer.load()?.id else { throw DiskFailure.rejected }
        let direct = route.companionID != nil || (route.address != nil && url.path.hasPrefix("/api/v2/"))
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
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: route == .internet ? 10 : 2)
        let (data, response) = try await self.data(request, route: route)
        if response.statusCode == 404, route == .internet { return nil }
        guard response.statusCode == 200, let result = try? JSONDecoder().decode(DiskCapabilities.self, from: data),
              result.version == 2, result.serverId.count == 32, result.lan == route.isLocal else { throw DiskFailure.rejected }
        if let id = route.companionID {
            guard result.serverId == id else { throw DiskFailure.rejected }
            return result
        }
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
