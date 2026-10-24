import Foundation
import Network
import UniformTypeIdentifiers

final class LocalUIServer {
    private let queue = DispatchQueue(label: "ru.atma.ui-http")
    private var listener: NWListener?
    private var resources: [String: URL] = [:]
    private var connections: [UUID: NWConnection] = [:]
    private(set) var port: UInt16 = 0

    static func resourceIndex(at directory: URL) throws -> [String: URL] {
        // iOS container paths may use aliases such as /var and /private/var.
        // Use the same canonical root for containment checks and relative keys.
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path + "/"
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw BrowserFailure.invalid("Bundled BrowserUI is missing.")
        }
        var resources: [String: URL] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true {
                let file = url.resolvingSymlinksInPath().standardizedFileURL
                guard file.path.hasPrefix(prefix) else { continue }
                resources[String(file.path.dropFirst(prefix.count))] = file
            }
        }
        guard resources["index.html"] != nil else { throw BrowserFailure.invalid("Bundled UI index.html is missing.") }
        return resources
    }

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            guard let root = Bundle.main.resourceURL?.appendingPathComponent("BrowserUI", isDirectory: true) else {
                throw BrowserFailure.invalid("Bundled BrowserUI is missing.")
            }
            resources = try Self.resourceIndex(at: root)
            let saved = UserDefaults.standard.integer(forKey: "atma.ui.loopback.port")
            port = (1024...65535).contains(saved) ? UInt16(saved) : UInt16.random(in: 49152...65535)
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            parameters.allowLocalEndpointReuse = false
            let listener = try NWListener(using: parameters)
            self.listener = listener
            var didComplete = false
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready where !didComplete:
                    didComplete = true
                    UserDefaults.standard.set(Int(self.port), forKey: "atma.ui.loopback.port")
                    DispatchQueue.main.async { completion(.success(URL(string: "http://127.0.0.1:\(self.port)/?context=ios")!)) }
                case .failed(let error) where !didComplete:
                    didComplete = true; listener.cancel()
                    DispatchQueue.main.async { completion(.failure(error)) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        } catch { completion(.failure(error)) }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.connections.removeValue(forKey: id) }
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = buffer
            accumulated.append(data ?? Data())
            guard accumulated.count <= 8192 else { self.respond(connection, status: "431 Request Header Fields Too Large"); return }
            if accumulated.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.handle(connection, request: accumulated)
            } else if complete || error != nil { connection.cancel() }
            else { self.receive(connection, buffer: accumulated) }
        }
    }

    private func handle(_ connection: NWConnection, request: Data) {
        guard let text = String(data: request, encoding: .utf8) else { respond(connection, status: "400 Bad Request"); return }
        let lines = text.components(separatedBy: "\r\n")
        let words = (lines.first ?? "").split(separator: " ")
        guard words.count == 3, words[0] == "GET" else { respond(connection, status: "405 Method Not Allowed"); return }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard hosts.count == 1, hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port)",
              let relative = UIResourcePath.relative(String(words[1])), let url = resources[relative],
              let data = try? Data(contentsOf: url) else { respond(connection, status: "404 Not Found"); return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        respond(connection, status: "200 OK", data: data, mime: mime)
    }

    private func respond(_ connection: NWConnection, status: String, data: Data = Data(), mime: String = "text/plain") {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-cache\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }

    deinit { listener?.cancel(); connections.values.forEach { $0.cancel() } }
}
