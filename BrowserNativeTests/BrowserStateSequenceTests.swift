import XCTest
import Foundation
@testable import ATMA

@MainActor
final class BrowserStateSequenceTests: XCTestCase {
    func testSnapshotsOrderPanelChangesAndRemainImmutable() throws {
        let suite = "atma.tests.state-sequence." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = BrowserController(model: BrowserModel(defaults: preferences))
        let first = controller.state()
        controller.panel = "settings"
        let opened = controller.state()
        controller.panel = nil
        let closed = controller.state()
        XCTAssertLessThan(try XCTUnwrap(first["sequence"] as? Int), try XCTUnwrap(opened["sequence"] as? Int))
        XCTAssertLessThan(try XCTUnwrap(opened["sequence"] as? Int), try XCTUnwrap(closed["sequence"] as? Int))
        XCTAssertEqual(opened["panel"] as? String, "settings")
        XCTAssertTrue(closed["panel"] is NSNull)
        XCTAssertTrue(first["panel"] is NSNull)
    }
}
