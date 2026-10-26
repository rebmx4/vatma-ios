import XCTest
import UIKit
import WebKit
@testable import ATMA

@MainActor
final class BrowserContentBlockerTests: XCTestCase {
    func testFirstWebsiteNavigationWaitsForContentRules() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let root = try await fixture.start()
        _ = try await fixture.open(root)
        XCTAssertTrue(fixture.controller.blocker.available)
        XCTAssertNil(fixture.controller.blocker.error)
    }

    func testBundledContentRulesCompile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "BrowserUI"))
        let rules = try String(contentsOf: url, encoding: .utf8)
        let compiled = expectation(description: "Bundled content rules compile")
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "atma.rules.test", encodedContentRuleList: rules) { list, error in
            XCTAssertNil(error)
            XCTAssertNotNil(list)
            compiled.fulfill()
        }
        wait(for: [compiled], timeout: 20)
    }

    func testYouTubeAdapterRemovesAdvertisementFieldsWithoutRemovingPlayback() async throws {
        let suite = "atma.tests.content-filter." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let savedPort = UserDefaults.standard.object(forKey: "atma.ui.loopback.port")
        UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port")
        let controller = BrowserController(model: BrowserModel(defaults: defaults))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        defer {
            for page in controller.renderers.values { controller.media.unregister(page); page.stopLoading() }
            controller.ui.stopLoading()
            controller.ui.configuration.userContentController.removeScriptMessageHandler(forName: "atma", contentWorld: .page)
            window.isHidden = true; window.rootViewController = nil
            defaults.removePersistentDomain(forName: suite)
            if let savedPort { UserDefaults.standard.set(savedPort, forKey: "atma.ui.loopback.port") }
            else { UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port") }
        }
        let capability = try XCTUnwrap(controller.state()["capabilities"] as? [String: Bool])
        XCTAssertNotNil(capability["contentBlocking"])
        XCTAssertNotNil(Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "BrowserUI"))
        XCTAssertNotNil(Bundle.main.url(forResource: "youtube-protection", withExtension: "js", subdirectory: "BrowserUI/assets"))

        let page = controller.renderer(for: controller.model.active)
        let url = URL(string: "https://www.youtube.com/watch?v=atma-test")!
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <div id="player-ads" class="video-ads">Website advertisement</div>
        <script>
        window.fixturePlayer=JSON.parse('{"videoDetails":{"videoId":"fixture"},"streamingData":{"formats":[]},"playerAds":[1],"adPlacements":[2],"adSlots":[3]}');
        window.fixtureReady=true;
        </script>
        """
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        page.loadSimulatedRequest(URLRequest(url: url), response: response, responseData: Data(html.utf8))
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if (try? await page.evaluateJavaScript("window.fixtureReady===true")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let result = try await page.evaluateJavaScript("({host:location.hostname,ads:window.fixturePlayer?.playerAds,placements:window.fixturePlayer?.adPlacements,slots:window.fixturePlayer?.adSlots,video:window.fixturePlayer?.videoDetails?.videoId,streams:window.fixturePlayer?.streamingData?.formats?.length,visible:getComputedStyle(document.getElementById('player-ads')).display!=='none',adapter:!!window.__atmaYouTubeProtection})")
        let state = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(state["host"] as? String, "www.youtube.com")
        XCTAssertNil(state["ads"])
        XCTAssertNil(state["placements"])
        XCTAssertNil(state["slots"])
        XCTAssertEqual(state["video"] as? String, "fixture")
        XCTAssertEqual(state["streams"] as? Int, 0)
        XCTAssertEqual(state["visible"] as? Bool, false)
        XCTAssertEqual(state["adapter"] as? Bool, true)
    }
}
