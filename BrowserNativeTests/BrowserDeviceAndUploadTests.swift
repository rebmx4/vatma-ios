import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserDeviceAndUploadTests: XCTestCase {
    func testGalaxyProfileIsSentOnFirstRequestAndAfterRedirect() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start(redirects: ["/mobile": "/a"])
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        _ = try await fixture.rpc("private-device", body: ["profileId": "galaxy-a54"])
        _ = try await fixture.rpc("open", body: ["url": root.appendingPathComponent("mobile").absoluteString])
        let page = try XCTUnwrap(fixture.controller.currentRenderer)
        try await fixture.wait("document.title === 'Page-a' && document.readyState === 'complete'", in: page)
        let profile = try XCTUnwrap(fixture.controller.model.profile("galaxy-a54"))
        let agent = try XCTUnwrap(profile["userAgent"] as? String)
        XCTAssertTrue(agent.contains("SM-A546B"))
        XCTAssertEqual(fixture.userAgents(at: "/mobile"), [agent])
        XCTAssertEqual(fixture.userAgents(at: "/a"), [agent])
        let javascriptAgent = try await fixture.script("return navigator.userAgent;", in: page) as? String
        XCTAssertEqual(javascriptAgent, agent)
        XCTAssertEqual(page.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)
    }

    func testSeparatePrivateSessionKeepsExistingPageAndItsLogin() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let first = try await fixture.open(root)
        let firstID = fixture.controller.model.activeTabId
        _ = try await fixture.script("document.cookie='session=a; path=/'; localStorage.setItem('session','a'); return true;", in: first)

        _ = try await fixture.rpc("private-device", body: ["profileId": "galaxy-a54", "separateSession": true])
        let secondID = fixture.controller.model.activeTabId
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertTrue(fixture.controller.renderers[firstID] === first)
        let second = try await fixture.open(root, path: "b")
        XCTAssertFalse(first.configuration.websiteDataStore === second.configuration.websiteDataStore)
        let secondIsClean = try await fixture.script("return !document.cookie && !localStorage.getItem('session');", in: second)
        XCTAssertEqual(secondIsClean as? Bool, true)
        _ = try await fixture.rpc("tabs/close", body: ["tabId": secondID])
        _ = try await fixture.rpc("tabs/select", body: ["tabId": firstID])
        XCTAssertTrue(fixture.controller.currentRenderer === first)
        let firstStillSignedIn = try await fixture.script(
            "return document.cookie.includes('session=a') && localStorage.getItem('session') === 'a';", in: first)
        XCTAssertEqual(firstStillSignedIn as? Bool, true)
    }

    func testUploadContinuesWhileAnotherShortcutIsSelected() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        let vk = ["url": root.appendingPathComponent("a").absoluteString, "shortcutId": "public:vk"]
        let dzen = ["url": root.appendingPathComponent("b").absoluteString, "shortcutId": "public:dzen"]
        _ = try await fixture.rpc("shortcut/open", body: vk)
        let firstID = fixture.controller.model.activeTabId
        let first = try XCTUnwrap(fixture.controller.currentRenderer)
        try await fixture.wait("document.title === 'Page-a'", in: first)
        let size = 8_388_608
        _ = try await fixture.script("""
            window.transfer = 'pending';
            fetch('/upload', {method:'POST', body: new Uint8Array(size)})
              .then(response => window.transfer = response.ok ? 'done' : 'failed')
              .catch(() => window.transfer = 'failed');
            return true;
            """, in: first, arguments: ["size": size])
        try await waitForUpload(fixture) { $0.bytes > 0 }

        _ = try await fixture.rpc("home")
        _ = try await fixture.rpc("shortcut/open", body: dzen)
        let secondID = fixture.controller.model.activeTabId
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertTrue(fixture.controller.renderers[firstID] === first)
        let bytesAtSwitch = fixture.uploadProgress().bytes
        XCTAssertLessThan(bytesAtSwitch, size, "The second tab must open while the upload is still in progress")
        try await waitForUpload(fixture) { $0.bytes > bytesAtSwitch }
        XCTAssertEqual(fixture.controller.model.activeTabId, secondID)
        try await waitForUpload(fixture) { $0.completed >= 1 }

        _ = try await fixture.rpc("home")
        _ = try await fixture.rpc("shortcut/open", body: vk)
        XCTAssertEqual(fixture.controller.model.activeTabId, firstID)
        XCTAssertTrue(fixture.controller.currentRenderer === first)
        try await fixture.wait("window.transfer === 'done'", in: first)
        XCTAssertEqual(fixture.uploadProgress().bytes, size)
        XCTAssertEqual(fixture.uploadProgress().requests, 1)
        XCTAssertEqual(fixture.userAgents(at: "/a").count, 1, "Reopening the shortcut must reuse its document")
    }

    private func waitForUpload(_ fixture: BrowserControllerFixture,
                               condition: (BrowserRenderingFixtureServer.Upload) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition(fixture.uploadProgress()) {
            guard Date() < deadline else { throw BrowserFailure.invalid("Timed out waiting for fixture upload.") }
            try await Task.sleep(for: .milliseconds(40))
        }
    }
}
