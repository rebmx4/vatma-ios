import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserPrivateNavigationTests: XCTestCase {
    func testPrivateCookiesRemainSeparateAndDisappearWhenTheSessionEnds() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let root = try await fixture.start()
        let ordinaryID = fixture.controller.model.activeTabId
        let ordinary = try await fixture.open(root)
        _ = try await fixture.script("document.cookie='session=ordinary;path=/';localStorage.setItem('session','ordinary');return true;", in: ordinary)
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let hidden = try await fixture.open(root)
        let initialPrivate = try await fixture.script("return {cookie:document.cookie,local:localStorage.getItem('session')};", in: hidden) as? [String: Any]
        XCTAssertEqual(initialPrivate?["cookie"] as? String, "")
        XCTAssertTrue(initialPrivate?["local"] is NSNull)
        _ = try await fixture.script("document.cookie='session=private;path=/';localStorage.setItem('session','private');return true;", in: hidden)
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let second = try await fixture.open(root)
        let shared = try await fixture.script("return document.cookie;", in: second) as? String
        XCTAssertEqual(shared, "session=private", "Private tabs share only their current private session")
        _ = try await fixture.rpc("tabs/private/close")
        XCTAssertFalse(fixture.controller.model.tabs.contains { $0.json["privateBrowsing"] as? Bool == true })
        _ = try await fixture.rpc("tabs/select", body: ["tabId": ordinaryID])
        let preserved = try await fixture.script("return {cookie:document.cookie,local:localStorage.getItem('session')};", in: ordinary) as? [String: Any]
        XCTAssertEqual(preserved?["cookie"] as? String, "session=ordinary")
        XCTAssertEqual(preserved?["local"] as? String, "ordinary")
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let fresh = try await fixture.open(root)
        let after = try await fixture.script("return {cookie:document.cookie,local:localStorage.getItem('session')};", in: fresh) as? [String: Any]
        XCTAssertEqual(after?["cookie"] as? String, "")
        XCTAssertTrue(after?["local"] is NSNull)
    }

    func testPrivateStartIsWhiteAndHomeReturnsToTheOrdinaryDesktop() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        _ = try await fixture.start()
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        try await fixture.wait("document.body.dataset.surface==='incognito'", in: fixture.controller.ui)
        let start = try await fixture.script("return {white:getComputedStyle(document.body).backgroundColor,title:document.querySelector('.incognito-card h1').textContent,input:!!document.getElementById('incognito-address')};", in: fixture.controller.ui) as? [String: Any]
        XCTAssertEqual(start?["white"] as? String, "rgb(255, 255, 255)")
        XCTAssertEqual(start?["title"] as? String, "Инкогнито")
        XCTAssertEqual(start?["input"] as? Bool, true)
        for theme in ["dark", "light"] {
            let colors = try await fixture.script("document.body.dataset.theme=theme;document.body.dataset.wallpaper='solid';return {bar:getComputedStyle(document.getElementById('browser-bar')).backgroundColor,button:getComputedStyle(document.getElementById('tabs-button')).color};", in: fixture.controller.ui, arguments: ["theme": theme]) as? [String: Any]
            XCTAssertEqual(colors?["bar"] as? String, "rgb(255, 255, 255)", theme + " private toolbar must stay white")
            XCTAssertEqual(colors?["button"] as? String, "rgb(37, 43, 52)", theme + " private toolbar buttons must remain visible")
        }
        _ = try await fixture.rpc("home")
        XCTAssertEqual(fixture.controller.state()["privateBrowsing"] as? Bool, false)
        try await fixture.wait("document.body.dataset.surface==='home'", in: fixture.controller.ui)
    }

    func testRealHistoryAndCompactHomeGlyphFollowNavigation() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let root = try await fixture.start()
        let page = try await fixture.open(root, webApp: true)
        try await fixture.wait("document.getElementById('go-back').disabled && document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        let compactGlyph = try await fixture.script("return getComputedStyle(document.querySelector('.home-brand')).display==='none' && getComputedStyle(document.querySelector('.home-glyph')).display!=='none';", in: fixture.controller.ui) as? Bool
        XCTAssertEqual(compactGlyph, true)
        _ = try await fixture.open(root, path: "b", webApp: true)
        try await fixture.wait("!document.getElementById('go-back').disabled && document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        page.goBack(); try await fixture.wait("document.title==='Page-a'", in: page)
        try await fixture.wait("document.getElementById('go-back').disabled && !document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        _ = try await fixture.open(root, path: "c", webApp: true)
        try await fixture.wait("document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        let state = fixture.controller.state()
        XCTAssertEqual(state["canGoBack"] as? Bool, true)
        XCTAssertEqual(state["canGoForward"] as? Bool, false)
    }

    func testFreshTabHistoryTracksPushStateReplaceStateAndSameDocumentBackForward() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let root = try await fixture.start()
        let page = try await fixture.open(root)
        try await fixture.wait("document.getElementById('go-back').disabled && document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        _ = try await fixture.script("history.replaceState({},'', '#replaced'); return true;", in: page)
        try await fixture.wait("document.getElementById('address').value.endsWith('#replaced') && document.getElementById('go-back').disabled && document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        _ = try await fixture.script("history.pushState({},'', '#next'); return true;", in: page)
        try await fixture.wait("document.getElementById('address').value.endsWith('#next') && !document.getElementById('go-back').disabled && document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        XCTAssertTrue(fixture.controller.model.active.url.hasSuffix("#next"))
        page.goBack()
        try await fixture.wait("document.getElementById('address').value.endsWith('#replaced') && document.getElementById('go-back').disabled && !document.getElementById('go-forward').disabled", in: fixture.controller.ui)
        page.goForward()
        try await fixture.wait("document.getElementById('address').value.endsWith('#next') && !document.getElementById('go-back').disabled && document.getElementById('go-forward').disabled", in: fixture.controller.ui)
    }

    func testPrivatePopupInheritsTheTemporaryWebsiteSession() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let root = try await fixture.start()
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let page = try await fixture.open(root)
        let popup = try fixture.controller.createSiteWindow(from: page, configuration: page.configuration, url: nil)
        let created = try XCTUnwrap(fixture.controller.model.tabs.last)
        XCTAssertEqual(created.json["privateBrowsing"] as? Bool, true)
        XCTAssertFalse(popup.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(popup.configuration.websiteDataStore === page.configuration.websiteDataStore)
    }
}
