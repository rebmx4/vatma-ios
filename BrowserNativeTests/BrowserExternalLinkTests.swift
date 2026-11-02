import XCTest
@testable import ATMA

final class BrowserExternalLinkTests: XCTestCase {
    func testWebsiteContactAndAppLinksRequireConfirmation() {
        for text in ["mailto:hello@example.com", "tel:+12025550123", "sms:+12025550123", "facetime:hello@example.com", "vk123://authorize?code=example"] {
            XCTAssertTrue(ExternalLinkPolicy.requiresConfirmation(URL(string: text)!), text)
        }
    }

    func testWebContentAndLocalOrExecutableSchemesCannotLaunchAnotherApp() {
        for text in ["https://example.com", "http://example.com", "about:blank", "file:///private/data", "data:text/html,hello", "javascript:alert(1)", "blob:https://example.com/example", "atma-ui://state"] {
            XCTAssertFalse(ExternalLinkPolicy.requiresConfirmation(URL(string: text)!), text)
        }
    }

    func testInstallationLinksCannotNavigateOrOpenAnotherApp() {
        for text in ["itms-services://install", "ITMS-SERVICES://install", "itms-apps://itunes.apple.com/app/id123"] {
            let installURL = URL(string: text)!
            XCTAssertTrue(ExternalLinkPolicy.isAppInstallationLink(installURL), text)
            XCTAssertFalse(ExternalLinkPolicy.requiresConfirmation(installURL), text)
            XCTAssertFalse(ExternalLinkPolicy.allowsSubframe(installURL), text)
            XCTAssertThrowsError(try AddressResolver.validated(installURL.absoluteString), text)
        }
    }

    func testOnlyWebContentSchemesCanNavigateSubframes() {
        for text in ["https://example.com", "about:blank", "blob:https://example.com/id", "data:text/html,hello"] {
            XCTAssertTrue(ExternalLinkPolicy.allowsSubframe(URL(string: text)!), text)
        }
        for text in ["file:///private/data", "atma-ui://state", "mailto:hello@example.com"] {
            XCTAssertFalse(ExternalLinkPolicy.allowsSubframe(URL(string: text)!), text)
        }
    }

    @MainActor
    func testWebsiteInstallLinkDoesNotLeaveBrowser() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let root = try await fixture.start()
        let page = try await fixture.open(root)
        let originalURL = try XCTUnwrap(page.url)
        _ = try await fixture.script("document.getElementById('install-app').click();return true;", in: page)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(page.url, originalURL)
        XCTAssertEqual(fixture.controller.model.active.url, originalURL.absoluteString)
        XCTAssertNil(fixture.controller.presentedViewController, "Installation must not offer an external-app dialog")
    }
}
