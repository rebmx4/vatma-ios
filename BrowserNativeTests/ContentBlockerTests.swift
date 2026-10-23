import XCTest
import WebKit
@testable import ATMA

final class ContentBlockerTests: XCTestCase {
    @MainActor
    func testBundledRulesCompileInWebKit() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "BrowserUI"))
        let rules = try String(contentsOf: url, encoding: .utf8)
        let compiled = expectation(description: "Bundled content blocker compiles")
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "atma.bundled-rules.test", encodedContentRuleList: rules) { list, error in
            XCTAssertNil(error, "The bundled rules must be supported by WebKit")
            XCTAssertNotNil(list)
            compiled.fulfill()
        }
        wait(for: [compiled], timeout: 20)
    }
}
