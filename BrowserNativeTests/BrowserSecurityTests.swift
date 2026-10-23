import XCTest
@testable import ATMA

final class BrowserSecurityTests: XCTestCase {
    func testAddressRejectsScriptAndEmbeddedCredentials() throws {
        for input in ["javascript:alert(1)", "data:text/html,hello", "file:///etc/passwd",
                      "https://user:secret@example.com", "ftp://example.com"] {
            XCTAssertThrowsError(try AddressResolver.resolve(input, engine: "google"), input)
        }
        XCTAssertEqual(try AddressResolver.resolve("example.com/a", engine: "google").absoluteString,
                       "https://example.com/a")
        let search = try AddressResolver.resolve("two words & more", engine: "google")
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       "two words & more")
    }

    func testCookieIdentityIncludesProfileDomainPathAndName() {
        let root = CookieIdentity.id(profile: "one", domain: ".example.com", path: "/", name: "sid")
        XCTAssertNotEqual(root, CookieIdentity.id(profile: "one", domain: ".example.com", path: "/admin", name: "sid"))
        XCTAssertNotEqual(root, CookieIdentity.id(profile: "two", domain: ".example.com", path: "/", name: "sid"))
        XCTAssertEqual(root.count, 64)
        XCTAssertEqual(root, CookieIdentity.id(profile: "one", domain: ".example.com", path: "/", name: "sid"))
        XCTAssertNotEqual(CookieIdentity.id(profile: "a|b", domain: "c", path: "/", name: "x"),
                          CookieIdentity.id(profile: "a", domain: "b|c", path: "/", name: "x"))
    }

    func testCookieSelectionDoesNotDeleteSameNameAtAnotherPath() throws {
        let root = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "sid", .value: "root"]))
        let admin = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/admin", .name: "sid", .value: "admin"]))
        let selected = CookieIdentity.select([root, admin], profile: "p", ids: [CookieIdentity.id(profile: "p", cookie: admin)])
        XCTAssertEqual(selected.map(\.path), ["/admin"])
        XCTAssertTrue(CookieIdentity.select([root], profile: "different", ids: [CookieIdentity.id(profile: "p", cookie: root)]).isEmpty)
    }

    func testResourcePathRejectsTraversalAndEncodedTraversal() {
        for path in ["/../secret", "/%2e%2e/secret", "/%252e%252e/secret", "/a\\b", "//secret", "/a/./b"] {
            XCTAssertNil(UIResourcePath.relative(path), path)
        }
        XCTAssertEqual(UIResourcePath.relative("/?context=ios"), "index.html")
        XCTAssertEqual(UIResourcePath.relative("/app.js?v=1"), "app.js")
    }
}
