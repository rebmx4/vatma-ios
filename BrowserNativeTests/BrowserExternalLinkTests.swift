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
        let installURL = URL(string: "itms" + "-services://install")!
        XCTAssertTrue(ExternalLinkPolicy.isAppInstallationLink(installURL))
        XCTAssertFalse(ExternalLinkPolicy.requiresConfirmation(installURL))
        XCTAssertFalse(ExternalLinkPolicy.allowsSubframe(installURL))
        XCTAssertThrowsError(try AddressResolver.validated(installURL.absoluteString))
    }

    func testOnlyWebContentSchemesCanNavigateSubframes() {
        for text in ["https://example.com", "about:blank", "blob:https://example.com/id", "data:text/html,hello"] {
            XCTAssertTrue(ExternalLinkPolicy.allowsSubframe(URL(string: text)!), text)
        }
        for text in ["file:///private/data", "atma-ui://state", "mailto:hello@example.com"] {
            XCTAssertFalse(ExternalLinkPolicy.allowsSubframe(URL(string: text)!), text)
        }
    }
}
