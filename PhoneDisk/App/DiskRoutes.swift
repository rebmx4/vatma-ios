import Combine
import Foundation
import Network
import WebKit

struct DiskRoute: Hashable, Codable {
    var address: String?
    var port: UInt16 = 0

    static let internet = DiskRoute(address:nil)
    static let sessionPrefix = (Bundle.main.bundleIdentifier ?? "ru.atma.phonedisk") + ".v2."

    var identifier: String { Self.sessionPrefix + (address.map { $0 + "." + String(port) } ?? "internet") }
    var isLocal: Bool { address != nil }

    var proxy: [ProxyConfiguration] {
        guard let address, let port = NWEndpoint.Port(rawValue:port), let host = IPv4Address(address) else { return [] }
        var configuration = ProxyConfiguration(httpCONNECTProxy:.hostPort(host:.ipv4(host),port:port))
        configuration.matchDomains = ["files.rynpro.ru"]
        configuration.allowFailover = false
        return [configuration]
    }

    static func local(_ address: String, port: UInt16) -> DiskRoute? {
        let numbers = address.split(separator:".").compactMap { UInt8($0) }
        guard numbers.count == 4, IPv4Address(address) != nil, port == 18113 else { return nil }
        guard numbers[0] == 10 || (numbers[0] == 172 && (16...31).contains(numbers[1])) ||
              (numbers[0] == 192 && numbers[1] == 168) else { return nil }
        return DiskRoute(address:address,port:port)
    }

    static func restore(_ identifier: String) -> DiskRoute? {
        guard identifier.hasPrefix(sessionPrefix) else { return nil }
        let value = String(identifier.dropFirst(sessionPrefix.count))
        if value == "internet" { return .internet }
        guard let boundary = value.lastIndex(of:"."), let port = UInt16(value[value.index(after:boundary)...]) else { return nil }
        return local(String(value[..<boundary]),port:port)
    }
}

struct DiskCapabilities: Decodable {
    var version: Int
    var serverId: String
    var lan: Bool
}

final class DiskRoutes: NSObject, ObservableObject, URLSessionTaskDelegate {
    static let shared = DiskRoutes()
    @Published private(set) var selected = DiskRoute.internet
    @Published private(set) var network = "Интернет"
    private var browser: NWBrowser?
    private var monitor: NWPathMonitor?
    private var candidates = Set<DiskRoute>()
    private var probes: [DiskRoute:URLSession] = [:]
    private var selection: Task<Void,Never>?
    private var cooldown: [DiskRoute:Date] = [:]
    private var rates: [DiskRoute:(rate:Double, samples:Int, time:Date, network:String)] = [:]
    private let serverKey = "phone-disk-server-identity"
    private let localKey = "phone-disk-last-local-route"

    var transferRoute: DiskRoute {
        if monitor == nil, let saved = UserDefaults.standard.string(forKey:localKey),let route = DiskRoute.restore(saved) {
            return route
        }
        return selected
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let kind = path.status != .satisfied ? "Ожидание сети" : path.usesInterfaceType(.cellular) ? "Мобильная сеть" : path.usesInterfaceType(.wifi) ? "Wi-Fi" : "Интернет"
                if kind != self.network { self.rates.removeAll() }
                self.network = kind
                self.choose()
            }
        }
        self.monitor = monitor
        monitor.start(queue:.global(qos:.utility))
        let browser = NWBrowser(for:.bonjourWithTXTRecord(type:"_phonedisk._tcp",domain:"local."), using:.tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.candidates = Set(results.compactMap { result in
                guard case .bonjour(let txt) = result.metadata, let address = txt.dictionary["address"],
                      let portValue = txt.dictionary["port"], let port = UInt16(portValue) else { return nil }
                return DiskRoute.local(address,port:port)
            })
            self.choose()
        }
        self.browser = browser
        browser.start(queue:.main)
    }

    func data(_ request: URLRequest, route: DiskRoute? = nil) async throws -> (Data,HTTPURLResponse) {
        guard Transfers.sameHost(request.url) else { throw DiskFailure.rejected }
        let route = route ?? transferRoute
        let session: URLSession
        if let saved = probes[route] { session = saved }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.proxyConfigurations = route.proxy
            configuration.httpShouldSetCookies = false
            session = URLSession(configuration:configuration,delegate:self,delegateQueue:.main)
            probes[route] = session
        }
        let (data,response) = try await session.data(for:request)
        guard let reply = response as? HTTPURLResponse, Transfers.sameHost(reply.url) else { throw DiskFailure.rejected }
        return (data,reply)
    }

    func capabilities(_ route: DiskRoute) async throws -> DiskCapabilities? {
        let url = Transfers.address("/api/v2/capabilities")
        let request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:2.5)
        let (data,response) = try await self.data(request,route:route)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200, let result = try? JSONDecoder().decode(DiskCapabilities.self,from:data),
              result.version == 2, result.serverId.count == 32, (!route.isLocal || result.lan) else { throw DiskFailure.rejected }
        let defaults = UserDefaults.standard
        if let known = defaults.string(forKey:serverKey), known != result.serverId { throw DiskFailure.rejected }
        defaults.set(result.serverId,forKey:serverKey)
        return result
    }

    private func choose() {
        selection?.cancel()
        if selected.isLocal && !candidates.contains(selected) { selected = .internet }
        if selected.isLocal { return }
        let ready = candidates.filter { (cooldown[$0] ?? .distantPast) <= Date() }.sorted { $0.identifier < $1.identifier }
        selection = Task { @MainActor in
            for route in ready.prefix(2) {
                if Task.isCancelled { return }
                if let _ = try? await capabilities(route), !Task.isCancelled, candidates.contains(route) {
                    selected = route
                    UserDefaults.standard.set(route.identifier,forKey:localKey)
                    return
                }
            }
        }
    }

    func failed(_ route: DiskRoute) {
        guard route.isLocal, transferRoute == route else { return }
        UserDefaults.standard.removeObject(forKey:localKey)
        cooldown[route] = Date().addingTimeInterval(15)
        selected = .internet
        choose()
        DispatchQueue.main.asyncAfter(deadline:.now()+15) { [weak self] in self?.choose() }
    }

    func record(_ route: DiskRoute, bytes: Int64, duration: Double) {
        guard bytes >= 1024 * 1024, duration > 0.1 else { return }
        let observed = Double(bytes) / duration
        let old = rates[route]
        let filtered = old.map { $0.rate * 0.6 + 0.4 * observed } ?? observed
        rates[route] = (filtered,(old?.samples ?? 0) + 1,Date(),network)
        guard selected == route, route.isLocal, network == "Wi-Fi", let local = rates[route], local.samples >= 3,
              let remote = rates[.internet], remote.network == network, Date().timeIntervalSince(remote.time) < 120,
              remote.rate > local.rate * 1.5 else { return }
        Task { @MainActor in
            if let _ = try? await capabilities(.internet), selected == route { failed(route) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
