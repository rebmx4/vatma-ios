import XCTest
@testable import ATMA

final class BrowserExternalLinkTests: XCTestCase {
    func testWebsiteContactAndAppLinksRequireConfirmation() {
        for text in ["mailto:hello@example.com", "tel:+12025550123", "sms:+12025550123", "facetime:hello@example.com", "vk123://authorize?code=example"] {
            XCTAssertTrue(ExternalLinkPolicy.requiresConfirmation(URL(string: text)!), text)
        }
    }

    func testWebContentAndLocalOrExecutableSchemesCannotLaunchAnotherApp() {
        for text in ["https://example.com", "http://example.com", "about:blank", "file:///private/data", "data:text/html,hello", "javascript:alert(1)", "blob:https://example.com/example", "itms-services://install", "atma-ui://state"] {
            XCTAssertFalse(ExternalLinkPolicy.requiresConfirmation(URL(string: text)!), text)
        }
    }
}
