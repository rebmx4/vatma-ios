import XCTest
import UIKit
import WebKit
@testable import ATMA

@MainActor
final class BrowserControllerFixture {
    let controller: BrowserController
    private let window: UIWindow
    private let defaults: UserDefaults
    private let suite: String
    private let savedPort: Any?
    private var http: BrowserRenderingFixtureServer?

    init() throws {
        suite = "atma.tests.private-browser." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        savedPort = UserDefaults.standard.object(forKey: "atma.ui.loopback.port")
        UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port")
        controller = BrowserController(model: BrowserModel(defaults: defaults))
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
    }

    func close() {
        http?.stop()
        for page in controller.renderers.values { controller.media.unregister(page); page.stopLoading() }
        controller.ui.stopLoading()
        controller.ui.configuration.userContentController.removeScriptMessageHandler(forName: "atma", contentWorld: .page)
        window.isHidden = true; window.rootViewController = nil
        if let savedPort { UserDefaults.standard.set(savedPort, forKey: "atma.ui.loopback.port") }
        else { UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port") }
        defaults.removePersistentDomain(forName: suite)
    }

    func start() async throws -> URL {
        let resources = Dictionary(uniqueKeysWithValues: ["a", "b", "c"].map { name in
            ("/" + name, Data("<!doctype html><html><head><title>Page-\(name)</title></head><body><h1>Page-\(name)</h1><input type='file' id='upload'></body></html>".utf8))
        })
        http = try BrowserRenderingFixtureServer(resources: resources)
        let root = try await http!.start()
        try await wait("!!document.getElementById('go-home') && !!document.body.dataset.mode", in: controller.ui)
        return root
    }

    func script(_ source: String, in page: WKWebView, arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            page.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    func rpc(_ action: String, body: [String: Any] = [:]) async throws -> Any? {
        try await script("return await window.webkit.messageHandlers.atma.postMessage({action,body});", in: controller.ui,
                         arguments: ["action": action, "body": body])
    }

    func open(_ root: URL, path: String = "a", webApp: Bool = false) async throws -> WKWebView {
        _ = try await rpc("open", body: ["url": root.appendingPathComponent(path).absoluteString, "webApp": webApp])
        let page = try XCTUnwrap(controller.currentRenderer)
        try await wait("document.title === 'Page-\(path)' && document.readyState === 'complete'", in: page)
        return page
    }

    func wait(_ expression: String, in page: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if (try? await script("return Boolean(\(expression));", in: page)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Browser fixture timed out: " + expression)
        throw NSError(domain: "ATMA.PrivateFixture", code: 1)
    }
}
