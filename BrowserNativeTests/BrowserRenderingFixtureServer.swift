import Foundation
import Network

final class BrowserRenderingFixtureServer {
    private let listener: NWListener
    private let resources: [String: Data]
    private let delays: [String: TimeInterval]
    private let queue = DispatchQueue(label: "atma.tests.http")
    private var connections: [UUID: NWConnection] = [:]

    init(resources: [String: Data], delays: [String: TimeInterval] = [:]) throws {
        self.resources = resources; self.delays = delays
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
            guard request.count <= 8192 else { connection.cancel(); return }
            guard request.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete || error != nil { connection.cancel() }
                else { self.receive(connection, buffer: request) }
                return
            }
            let path = String(data: request, encoding: .utf8)?.components(separatedBy: " ").dropFirst().first ?? ""
            let body = self.resources[path] ?? Data("Not found".utf8)
            let status = self.resources[path] == nil ? "404 Not Found" : "200 OK"
            let mime = path.hasSuffix(".png") ? "image/png" : path.hasSuffix(".json") ? "application/manifest+json" : "text/html; charset=utf-8"
            let header = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let send = { connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() }) }
            if let delay = self.delays[path] { self.queue.asyncAfter(deadline: .now() + delay, execute: send) }
            else { send() }
        }
    }
}
