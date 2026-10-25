import XCTest
@testable import ATMA

final class BrowserUnreadTests: XCTestCase {
    @MainActor
    func testProviderAllowlistRejectsLookalikeHostsAndInsecurePages() {
        XCTAssertTrue(BrowserUnread.resourceAvailable)
        XCTAssertEqual(BrowserUnread.provider(for: URL(string: "https://m.vk.ru/feed")), "vk")
        XCTAssertEqual(BrowserUnread.provider(for: URL(string: "https://vk.com/im")), "vk")
        XCTAssertEqual(BrowserUnread.provider(for: URL(string: "https://www.avito.ru/profile/messenger")), "avito")
        XCTAssertNil(BrowserUnread.provider(for: URL(string: "https://vk.ru.evil.example/im")))
        XCTAssertNil(BrowserUnread.provider(for: URL(string: "http://m.vk.ru/im")))
    }
}
