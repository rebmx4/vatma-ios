import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserWindowTests: XCTestCase {
    private var controller: BrowserController!
    private var preferences: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "atma.tests.windows." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        controller = BrowserController(model: BrowserModel(defaults: preferences))
        controller.loadViewIfNeeded()
    }

    override func tearDown() {
        for renderer in controller.renderers.values { controller.media.unregister(renderer) }
        controller.ui.configuration.userContentController.removeScriptMessageHandler(forName: "atma", contentWorld: .page)
        controller = nil
        preferences.removePersistentDomain(forName: suite)
        preferences = nil
        super.tearDown()
    }

    func testWindowKeepsItsSourceProfileAndWebKitConfigurationWhenAnotherTabIsActive() throws {
        try controller.changeProfile("iphone-13-pro-max")
        let sourceID = controller.model.activeTabId
        let source = controller.renderer(for: controller.model.active)
        controller.newTab(profile: BrowserModel.actualProfile)
        let configuration = WKWebViewConfiguration()
        configuration.processPool = source.configuration.processPool
        configuration.websiteDataStore = source.configuration.websiteDataStore
        let popup = try controller.createSiteWindow(from: source, configuration: configuration, url: nil)

        XCTAssertEqual(controller.model.active.profileId, "iphone-13-pro-max")
        XCTAssertEqual(controller.model.active.url, "about:blank")
        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)
        XCTAssertTrue(popup.configuration.websiteDataStore === source.configuration.websiteDataStore)
        XCTAssertFalse(popup.configuration.userContentController === source.configuration.userContentController)
        XCTAssertEqual(controller.mode, "browse")
        controller.webViewDidClose(popup)
        XCTAssertEqual(controller.model.activeTabId, sourceID)
    }

    func testRejectedWindowDoesNotCreateOrSelectATab() throws {
        let source = controller.renderer(for: controller.model.active)
        let activeID = controller.model.activeTabId
        for address in ["javascript:alert(1)", "file:///private", "data:text/html,hello",
                        "about:config", "https://user:secret@example.com"] {
            XCTAssertThrowsError(try controller.createSiteWindow(from: source,
                configuration: WKWebViewConfiguration(), url: URL(string: address)))
            XCTAssertEqual(controller.model.tabs.count, 1)
            XCTAssertEqual(controller.model.activeTabId, activeID)
        }
        XCTAssertThrowsError(try controller.createSiteWindow(from: controller.ui,
            configuration: WKWebViewConfiguration(), url: URL(string: "https://example.com")))
    }

    func testBlankWindowCanChangeProfileAndRecreateItsRenderer() throws {
        let source = controller.renderer(for: controller.model.active)
        _ = try controller.createSiteWindow(from: source, configuration: WKWebViewConfiguration(), url: nil)
        let windowID = controller.model.activeTabId
        try controller.changeProfile("windows-chrome")
        XCTAssertEqual(controller.model.activeTabId, windowID)
        XCTAssertEqual(controller.model.active.url, "about:blank")
        XCTAssertEqual(controller.model.active.profileId, "windows-chrome")
        let renderer = try XCTUnwrap(controller.currentRenderer)
        controller.media.unregister(renderer)
        renderer.stopLoading()
        renderer.removeFromSuperview()
        controller.renderers.removeValue(forKey: windowID)
        try controller.selectTab(windowID)
        XCTAssertNotNil(controller.currentRenderer)
        XCTAssertEqual(controller.mode, "browse")
    }

    func testProfilesSetConsistentUserAgentAndPageModeWithoutChangingTheUI() throws {
        let uiConfiguration = controller.ui.configuration
        let actual = controller.renderer(for: controller.model.active)
        XCTAssertNil(actual.customUserAgent)
        XCTAssertEqual(actual.configuration.defaultWebpagePreferences.preferredContentMode, .recommended)

        try controller.changeProfile("windows-chrome")
        let desktop = controller.renderer(for: controller.model.active)
        XCTAssertTrue(try XCTUnwrap(desktop.customUserAgent).contains("Windows NT 10.0"))
        XCTAssertEqual(desktop.configuration.defaultWebpagePreferences.preferredContentMode, .desktop)

        try controller.changeProfile("iphone-13-pro-max")
        let mobile = controller.renderer(for: controller.model.active)
        XCTAssertTrue(try XCTUnwrap(mobile.customUserAgent).contains("iPhone"))
        XCTAssertEqual(mobile.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)
        XCTAssertEqual(controller.ui.configuration.defaultWebpagePreferences.preferredContentMode,
                       uiConfiguration.defaultWebpagePreferences.preferredContentMode)
        XCTAssertNil(controller.ui.customUserAgent)
    }

    func testProfileStorageAndGoogleDefaultSurviveModelRecreation() {
        XCTAssertEqual(controller.model.preferences.searchEngine, "google")
        _ = controller.model.store(for: BrowserModel.actualProfile)
        let firstID = preferences.string(forKey: "atma.native.store.actual-device")
        let restored = BrowserModel(defaults: preferences)
        _ = restored.store(for: BrowserModel.actualProfile)
        XCTAssertNotNil(firstID)
        XCTAssertEqual(preferences.string(forKey: "atma.native.store.actual-device"), firstID)
        _ = restored.store(for: "iphone-13-pro-max")
        XCTAssertNotEqual(preferences.string(forKey: "atma.native.store.iphone-13-pro-max"), firstID)
        XCTAssertEqual(restored.preferences.searchEngine, "google")
    }

    func testRealWindowOpenCanReturnAMessageToItsOpener() async {
        let received = expectation(description: "The site receives its popup's message")
        let result = WindowResult { value in
            XCTAssertEqual(value, "opener-connected")
            received.fulfill()
        }
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let source = controller.renderer(for: controller.model.active, configuration: configuration)
        source.configuration.userContentController.add(result, name: "windowFixture")
        defer { source.configuration.userContentController.removeScriptMessageHandler(forName: "windowFixture") }
        source.loadHTMLString("""
            <html><body><script>
            const child = window.open('about:blank');
            const report = value => window.webkit.messageHandlers.windowFixture.postMessage(value);
            if (!child) report('missing-window');
            else {
                window.addEventListener('message', event => {
                    if (event.data !== 'atma-window-fixture') return;
                    report(event.source === child ? 'opener-connected' : 'wrong-window');
                    child.close();
                });
                child.document.write("<script>window.opener.postMessage('atma-window-fixture','*');<" + "/script>");
                child.document.close();
            }
            </script></body></html>
            """, baseURL: nil)
        await fulfillment(of: [received], timeout: 15)
    }

    private final class WindowResult: NSObject, WKScriptMessageHandler {
        let receive: (String) -> Void
        init(_ receive: @escaping (String) -> Void) { self.receive = receive }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            receive(message.body as? String ?? "invalid-message")
        }
    }
}
