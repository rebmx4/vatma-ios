import XCTest
import UIKit
import WebKit
import Network
import AVFoundation
@testable import ATMA

@MainActor
final class BrowserRenderingTests: XCTestCase {
    private var controller: BrowserController!
    private var window: UIWindow!
    private var preferences: UserDefaults!
    private var suite: String!
    private var savedPort: Any?
    private var fixture: BrowserRenderingFixtureServer!

    override func setUpWithError() throws {
        suite = "atma.tests.rendering." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        // The hosted app already owns its listener. Give this test controller
        // a separate loopback origin instead of trying to bind that same port.
        savedPort = UserDefaults.standard.object(forKey: "atma.ui.loopback.port")
        UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port")
        controller = BrowserController(model: BrowserModel(defaults: preferences))
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
    }

    override func tearDownWithError() throws {
        fixture?.stop()
        for page in controller.renderers.values {
            controller.media.unregister(page)
            page.stopLoading()
        }
        controller.ui.stopLoading()
        controller.ui.configuration.userContentController.removeScriptMessageHandler(forName: "atma", contentWorld: .page)
        window.isHidden = true
        window.rootViewController = nil
        window = nil
        controller = nil
        if let savedPort { UserDefaults.standard.set(savedPort, forKey: "atma.ui.loopback.port") }
        else { UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port") }
        preferences.removePersistentDomain(forName: suite)
        preferences = nil
    }

    func testPlaybackContinuesAcrossPeriodicNativeMediaStateReports() async throws {
        let page = try await openVideo()
        let startValue = try await script("return document.querySelector('video').currentTime;", in: page)
        let start = try XCTUnwrap(startValue as? Double)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let statusValue = try await script("const v=document.querySelector('video'); return {paused:v.paused,time:v.currentTime};", in: page)
        let status = try XCTUnwrap(statusValue as? [String: Any])
        XCTAssertEqual(status["paused"] as? Bool, false, "State reporting must not stop the website's player")
        XCTAssertGreaterThan(try XCTUnwrap(status["time"] as? Double), start + 2)
    }

    func testPassiveInterruptionNoticeDoesNotManufactureAJavaScriptPause() async throws {
        let page = try await openVideo()
        // This notification deliberately does not interrupt WebKit's player.
        // WebKit owns actual system interruptions; an observer must not create
        // an additional delayed pause command from a passive notification.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(nanoseconds: 800_000_000)
        let paused = try await script("return document.querySelector('video').paused;", in: page) as? Bool
        XCTAssertEqual(paused, false, "The browser must not enqueue a second page pause from an audio-session notice")
    }

    func testOverviewShowsBothVisitedPagesInsteadOfSnapshotsOfHiddenRenderers() async throws {
        let url = try await startFixture(video: false)
        try await waitForUI()
        try controller.open(url.appendingPathComponent("red").absoluteString)
        let redID = controller.model.activeTabId
        try await waitForPaint(in: XCTUnwrap(controller.currentRenderer), color: "rgb(220, 38, 40)")
        _ = try await rpc("tabs/new")
        try controller.open(url.appendingPathComponent("blue").absoluteString)
        let blueID = controller.model.activeTabId
        try await waitForPaint(in: XCTUnwrap(controller.currentRenderer), color: "rgb(30, 70, 220)")
        _ = try await rpc("panel", body: ["panel": "tabs"])
        try await waitFor("document.querySelectorAll('.tab-shot').length===2 && [...document.querySelectorAll('.tab-shot')].every(image=>image.complete && image.naturalWidth>0)", in: controller.ui)
        let imagesValue = try await script("return Object.fromEntries([...document.querySelectorAll('.tab-card')].map(card=>[card.dataset.tabId,card.querySelector('.tab-shot')?.src]));", in: controller.ui)
        let images = try XCTUnwrap(imagesValue as? [String: String])
        let red = try averageRGB(try XCTUnwrap(images[redID]))
        let blue = try averageRGB(try XCTUnwrap(images[blueID]))
        XCTAssertGreaterThan(red[0], 150); XCTAssertLessThan(red[1], 110)
        XCTAssertGreaterThan(blue[2], 150); XCTAssertLessThan(blue[0], 110)
        _ = try await script("window.__originalTabCard=document.querySelector('.tab-card'); return true;", in: controller.ui)
        for _ in 0..<5 { controller.publish() }
        try await Task.sleep(nanoseconds: 500_000_000)
        let preserved = try await script("return window.__originalTabCard===document.querySelector('.tab-card');", in: controller.ui) as? Bool
        XCTAssertEqual(preserved, true, "Native state reports must preserve the displayed tab card")
    }

    private func openVideo() async throws -> WKWebView {
        let url = try await startFixture(video: true)
        try controller.open(url.appendingPathComponent("video").absoluteString)
        let page = try XCTUnwrap(controller.currentRenderer)
        try await waitFor("document.querySelector('video')?.readyState>=1 && !!window.__atmaMediaPage", in: page)
        _ = try await script("await document.querySelector('video').play(); return true;", in: page)
        try await waitFor("document.querySelector('video').currentTime>0.3 && !document.querySelector('video').paused", in: page)
        XCTAssertEqual(controller.media.state["available"] as? Bool, true, "The real production media bridge must own the playing page")
        return page
    }

    private func startFixture(video: Bool) async throws -> URL {
        var resources: [String: Data] = [:]
        for (path, color) in [("/red", "rgb(220,38,40)"), ("/blue", "rgb(30,70,220)")] {
            resources[path] = Data("<!doctype html><html><head><title>\(path) fixture</title><style>html,body{margin:0;width:100%;height:100%;background:\(color)}</style></head><body></body></html>".utf8)
        }
        if video {
            let bundle = Bundle(for: BrowserRenderingTests.self)
            let mediaURL = try XCTUnwrap(bundle.url(forResource: "playback", withExtension: "mp4"))
            let media = try Data(contentsOf: mediaURL).base64EncodedString()
            resources["/video"] = Data("<!doctype html><html><head><title>Playback fixture</title></head><body><video playsinline controls preload='auto' width='320' height='180' src='data:video/mp4;base64,\(media)'></video></body></html>".utf8)
        }
        fixture = try BrowserRenderingFixtureServer(resources: resources)
        return try await fixture.start()
    }

    private func waitForUI() async throws {
        try await waitFor("!!document.getElementById('go-home') && !!document.body.dataset.mode", in: controller.ui)
    }

    private func waitForPaint(in page: WKWebView, color: String) async throws {
        let encoded = String(data: try JSONSerialization.data(withJSONObject: [color]), encoding: .utf8)!
        try await waitFor("document.readyState==='complete' && getComputedStyle(document.body).backgroundColor===\(encoded)[0]", in: page)
        _ = try await script("await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))); return true;", in: page)
    }

    private func waitFor(_ expression: String, in page: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if (try? await script("return Boolean(\(expression));", in: page)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let details = try? await script("const v=document.querySelector('video'); return JSON.stringify({url:location.href,ready:document.readyState,mediaBridge:!!window.__atmaMediaPage,video:v?{ready:v.readyState,network:v.networkState,paused:v.paused,time:v.currentTime,error:v.error?.code}:null});", in: page)
        XCTFail("Fixture condition timed out: \(expression); details: \(String(describing: details))")
        throw NSError(domain: "ATMA.RenderingFixture", code: 1)
    }

    private func script(_ source: String, in page: WKWebView, arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            page.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private func rpc(_ action: String, body: [String: Any] = [:]) async throws -> Any? {
        try await script("return await window.webkit.messageHandlers.atma.postMessage({action,body});", in: controller.ui, arguments: ["action": action, "body": body])
    }

    private func averageRGB(_ source: String) throws -> [UInt8] {
        let encoded = try XCTUnwrap(source.split(separator: ",", maxSplits: 1).last)
        let bytes = try XCTUnwrap(Data(base64Encoded: String(encoded)))
        let image = try XCTUnwrap(UIImage(data: bytes)?.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }
}

private final class BrowserRenderingFixtureServer {
    private let listener: NWListener
    private let resources: [String: Data]
    private let queue = DispatchQueue(label: "atma.tests.http")
    private var connections: [UUID: NWConnection] = [:]

    init(resources: [String: Data]) throws {
        self.resources = resources
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
            let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
