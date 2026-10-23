import XCTest
@testable import ATMA

final class BrowserAppearanceTests: XCTestCase {
    func testPrimaryIconUsesTheSystemDefault() throws {
        XCTAssertNil(try BrowserAppearancePolicy.assetName(for: "default"))
    }

    func testEveryUIIconMapsToItsPackagedOSAsset() throws {
        for index in 1...10 {
            XCTAssertEqual(try BrowserAppearancePolicy.assetName(for: String(format: "a1-%02d", index)),
                           String(format: "AppIconA1%02d", index))
        }
    }

    func testUnlistedIconNamesCannotReachUIKit() {
        for icon in ["", "a1-00", "a1-11", "AppIconA101", "../AppIcon", "a1-1"] {
            XCTAssertThrowsError(try BrowserAppearancePolicy.assetName(for: icon))
        }
    }
}
