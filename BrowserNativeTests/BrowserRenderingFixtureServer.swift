import Foundation
import Network

final class BrowserRenderingFixtureServer {
    struct Upload {
        var bytes = 0
        var requests = 0
        var completed = 0
    }

    private let listener: NWListener
    private let resources: [String: Data]
    private let delays: [String: TimeInterval]
    private let redirects: [String: String]
    private let queue = DispatchQueue(label: "atma.tests.http")
    private var connections: [UUID: NWConnection] = [:]
    private var agents: [String: [String]] = [:]
    private var upload = Upload()

    init(resources: [String: Data], delays: [String: TimeInterval] = [:], redirects: [String: String] = [:]) throws {
        self.resources = resources; self.delays = delays
        self.redirects = redirects
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)/")!)
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        queue.async { self.connections.values.forEach { $0.cancel() }; self.connections.removeAll() }
    }

    func userAgents(at path: String) -> [String] { queue.sync { agents[path, default: []] } }
    func uploadProgress() -> Upload { queue.sync { upload } }

    private func accept(_ connection: NWConnection) {
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.connections.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var request = buffer; request.append(data ?? Data())
            guard let boundary = request.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil || request.count > 8192 { connection.cancel() }
                else { self.receive(connection, buffer: request) }
                return
            }
            let header = String(decoding: request[..<boundary.lowerBound], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let start = lines.first?.split(separator: " ") ?? []
            guard start.count == 3 else { connection.cancel(); return }
            let path = String(start[1])
            if let agent = self.headerValue("User-Agent", lines) { self.agents[path, default: []].append(agent) }
            if start[0] == "POST", path == "/upload",
               let length = self.headerValue("Content-Length", lines).flatMap(Int.init), (1...8_388_608).contains(length) {
                self.upload.requests += 1
                self.receiveUpload(connection, remaining: length, count: request.count - boundary.upperBound)
                return
            }
            if let destination = self.redirects[path] {
                let response = "HTTP/1.1 302 Found\r\nLocation: \(destination)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let body = self.resources[path] ?? Data("Not found".utf8)
            let status = self.resources[path] == nil ? "404 Not Found" : "200 OK"
            let mime = path.hasSuffix(".png") ? "image/png" : path.hasSuffix(".json") ? "application/manifest+json" : "text/html; charset=utf-8"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let send = { connection.send(content: Data(response.utf8) + body, completion: .contentProcessed { _ in connection.cancel() }) }
            if let delay = self.delays[path] { self.queue.asyncAfter(deadline: .now() + delay, execute: send) }
            else { send() }
        }
    }

    private func headerValue(_ name: String, _ lines: [String]) -> String? {
        let prefix = name.lowercased() + ":"
        return lines.dropFirst().first { $0.lowercased().hasPrefix(prefix) }
            .map { $0.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) }
    }

    private func receiveUpload(_ connection: NWConnection, remaining: Int, count: Int) {
        let accepted = min(remaining, count)
        upload.bytes += accepted
        let next = remaining - accepted
        if next == 0 {
            upload.completed += 1
            let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK".utf8)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        queue.asyncAfter(deadline: .now() + 0.045) { [weak self] in
            connection.receive(minimumIncompleteLength: 1, maximumLength: min(65_536, next)) { [weak self] data, _, _, error in
                guard let self, let data, !data.isEmpty, error == nil else { connection.cancel(); return }
                self.receiveUpload(connection, remaining: next, count: data.count)
            }
        }
    }
}
