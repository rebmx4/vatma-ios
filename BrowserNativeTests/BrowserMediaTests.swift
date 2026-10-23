import XCTest
@testable import ATMA

final class BrowserMediaTests: XCTestCase {
    func testOnlyMediaCommandsAndFinitePositionsAreAccepted() throws {
        XCTAssertEqual(try BrowserMediaPolicy.command(["type": "skip", "seconds": -10])["type"] as? String, "skip")
        XCTAssertThrowsError(try BrowserMediaPolicy.command(["type": "navigate", "url": "file:///private"]))
        XCTAssertThrowsError(try BrowserMediaPolicy.command(["type": "seek", "seconds": Double.nan]))
        XCTAssertThrowsError(try BrowserMediaPolicy.command(["type": "seek", "seconds": true]))
    }

    func testUntrustedStateIsBoundedAndNeverReturnsMediaURLs() throws {
        let parsed = try BrowserMediaPolicy.snapshot(["version": 1, "available": true, "title": String(repeating: "x", count: 900),
            "paused": false, "currentTime": 4.0, "duration": 100.0, "pip": false, "pipAvailable": true,
            "url": "https://media.invalid/private-token"])
        XCTAssertEqual((parsed["title"] as? String)?.count, 200)
        XCTAssertNil(parsed["url"])
        XCTAssertThrowsError(try BrowserMediaPolicy.snapshot(["version": 1, "available": true, "currentTime": Double.infinity]))
    }

    func testMediaMessageOriginRequiresTheExactMainDocument() {
        let page = URL(string: "https://www.youtube.com/watch?v=fixture")!
        XCTAssertTrue(BrowserMediaPolicy.matches(page: page, scheme: "https", host: "www.youtube.com", port: 443))
        XCTAssertTrue(BrowserMediaPolicy.matches(page: page, scheme: "https", host: "www.youtube.com", port: 0))
        XCTAssertFalse(BrowserMediaPolicy.matches(page: page, scheme: "https", host: "youtube.com.example.invalid", port: 443))
        XCTAssertFalse(BrowserMediaPolicy.matches(page: page, scheme: "http", host: "www.youtube.com", port: 80))
    }
}
