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

    func testPairedBackgroundSessionRestoresTheComputerAndAddress() throws {
        let id = "0123456789abcdef0123456789abcdef"
        let route = try XCTUnwrap(DiskRoute.companion(id: id, host: "192.168.1.32", port: 18119))
        let tailnet = try XCTUnwrap(DiskRoute.companion(id: id, host: "100.71.20.3", port: 18119))
        XCTAssertEqual(DiskRoute.restore(route.backgroundIdentifier), route)
        XCTAssertEqual(DiskRoute.restore(tailnet.backgroundIdentifier), tailnet)
        XCTAssertEqual(route.webOrigin?.absoluteString, "https://192.168.1.32:18119/")
        XCTAssertTrue(route.isLocal)
        XCTAssertTrue(tailnet.isTailnet)
        XCTAssertFalse(route.acceptsBackgroundURL(tailnet.webOrigin))
    }

    func testPairingQRExpectsAPrivateAddressAndExactComputerIdentity() throws {
        let id = "0123456789abcdef0123456789abcdef"
        let fingerprint = String(repeating: "9", count: 64)
        let invitation = "phonedisk://pair?v=1&id=\(id)&host=192.168.1.32&port=18119&pin=\(fingerprint)&code=\(String(repeating: "q", count: 43))"
        XCTAssertEqual(PairInvitation(invitation)?.id, id)
        XCTAssertNil(PairInvitation(invitation + "&id=" + id))
        XCTAssertNil(PairInvitation(invitation.replacingOccurrences(of: "192.168.1.32", with: "203.0.113.40")))
        XCTAssertNil(PairInvitation(invitation.replacingOccurrences(of: "192.168.1.32", with: "100.71.20.3")))
    }

    func testCameraPairingLinkKeepsTheCodeInTheFragment() throws {
        let id = "0123456789abcdef0123456789abcdef"
        let pin = String(repeating: "9", count: 64)
        let code = String(repeating: "q", count: 43)
        let fields = "v=1&id=\(id)&host=192.168.1.32&port=18119&pin=\(pin)&code=\(code)&tailnet=100.71.20.3"
        let path = "https://rynpro.ru/disk/connect/"
        let invitation = try XCTUnwrap(PairInvitation(path + "#" + fields))
        XCTAssertEqual(invitation.id, id)
        XCTAssertEqual(invitation.host, "192.168.1.32")
        XCTAssertEqual(invitation.port, 18119)
        XCTAssertEqual(invitation.fingerprint, pin)
        XCTAssertEqual(invitation.code, code)
        XCTAssertEqual(invitation.tailnet, "100.71.20.3")
        XCTAssertNil(PairInvitation(path + "?" + fields))
        XCTAssertNil(PairInvitation(path + "?extra=1#" + fields))
        XCTAssertNil(PairInvitation(path + "#" + fields + "&code=" + code))
        XCTAssertNil(PairInvitation(path + "#" + fields + "#other-fragment"))
        XCTAssertNil(PairInvitation("http://rynpro.ru/disk/connect/#" + fields))
        XCTAssertNil(PairInvitation("https://www.rynpro.ru/disk/connect/#" + fields))
        XCTAssertNil(PairInvitation("https://rynpro.ru:443/disk/connect/#" + fields))
        XCTAssertNil(PairInvitation("https://rynpro.ru/disk/#" + fields))
    }
}
