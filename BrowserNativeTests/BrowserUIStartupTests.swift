import WebKit
import XCTest
@testable import ATMA

@MainActor
final class BrowserUIStartupTests: XCTestCase {
    func testMissingStylesheetRetriesWithoutChangingOrigin() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let browser = fixture.controller
        let source = """
        if (location.protocol === 'http:') {
            const key = 'atma-test-startup-attempts';
            const attempts = Number(sessionStorage.getItem(key)) + 1;
            sessionStorage.setItem(key, String(attempts));
            if (attempts === 1) {
                const sheet = Object.getOwnPropertyDescriptor(HTMLLinkElement.prototype, 'sheet').get;
                Object.defineProperty(HTMLLinkElement.prototype, 'sheet', {
                    get() { return this.getAttribute('href') === '/incognito.css' ? null : sheet.call(this); }
                });
            }
        }
        """
        browser.ui.configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        XCTAssertFalse(browser.uiStartup.isReady)
        try await fixture.wait("sessionStorage.getItem('atma-test-startup-attempts') === '2'", in: browser.ui)
        let deadline = Date().addingTimeInterval(8)
        while !browser.uiStartup.isReady && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(browser.uiStartup.isReady)
        let url = try XCTUnwrap(browser.ui.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "desktopRegion" }?.value,
                       Locale.autoupdatingCurrent.region?.identifier)
        let ready = try await fixture.script("""
            return !!document.body.dataset.mode && [...document.styleSheets].some(sheet => sheet.href?.endsWith('/incognito.css'));
            """, in: browser.ui)
        XCTAssertEqual(ready as? Bool, true)
    }
}
