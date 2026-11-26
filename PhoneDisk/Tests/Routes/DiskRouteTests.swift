import XCTest
@testable import PhoneDisk

final class DiskRouteTests: XCTestCase {
    @MainActor func testHealthyLANDoesNotProbeTailscale() async throws {
        let lan = try XCTUnwrap(DiskRoute.local("10.250.21.246", port: 18113))
        let tailnet = try XCTUnwrap(DiskRoute.tailnet)
        var attempts: [DiskRoute] = []
        let route = await DiskRoutes.firstReachable(local: [lan], fallback: tailnet) {
            attempts.append($0)
            return true
        }
        XCTAssertEqual(attempts, [lan])
        XCTAssertEqual(route, lan)
    }

    @MainActor func testUnavailableLANUsesTheExistingTailnetEndpoint() async throws {
        let lan = try XCTUnwrap(DiskRoute.local("192.168.1.40", port: 18113))
        let tailnet = try XCTUnwrap(DiskRoute.tailnet)
        var attempts: [DiskRoute] = []
        let route = await DiskRoutes.firstReachable(local: [lan], fallback: tailnet) {
            attempts.append($0)
            return $0 == tailnet
        }
        XCTAssertEqual(attempts, [lan, tailnet])
        XCTAssertEqual(route, tailnet)
        XCTAssertEqual(DiskRoute.restore(tailnet.backgroundIdentifier), tailnet)
        XCTAssertFalse(tailnet.isLocal)
        XCTAssertNil(DiskRoute.local(try XCTUnwrap(tailnet.address), port: tailnet.port))
    }

    @MainActor func testNoRouteWhenBothChecksFail() async throws {
        let lan = try XCTUnwrap(DiskRoute.local("10.250.21.246", port: 18113))
        let route = await DiskRoutes.firstReachable(local: [lan], fallback: DiskRoute.tailnet) { _ in false }
        XCTAssertNil(route)
    }
}
