import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserShortcutProfileTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var model: BrowserModel!

    override func setUp() {
        suite = "atma.tests.website-session." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        model = BrowserModel(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        model = nil; defaults = nil
    }

    func testOnlyTheActualDeviceExistsWithoutABundledDeviceCatalogue() {
        XCTAssertEqual(model.profiles.compactMap { $0["id"] as? String }, [BrowserModel.actualProfile])
        XCTAssertNil(Bundle.main.url(forResource: "profiles", withExtension: "json", subdirectory: "BrowserUI"))
    }

    func testLegacyKeysCannotCreateAnAlternateCookieSession() async throws {
        let store = model.store(for: BrowserModel.actualProfile)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "account.example.invalid", .path: "/",
                                                         .name: "session", .value: "retained-login", .secure: "TRUE"]))
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
        let same = model.store(for: "iphone-13-pro-max")
        XCTAssertTrue(same === store)
        XCTAssertNil(defaults.string(forKey: "atma.native.store.iphone-13-pro-max"))
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            same.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(cookies.first { $0.name == "session" }?.value, "retained-login")
    }

    func testWebsiteSessionIdentifierAndActualDeviceSurviveRestoration() {
        _ = model.store(for: BrowserModel.actualProfile)
        let identifier = defaults.string(forKey: "atma.native.store.actual-device")
        model.tabs[0].profileId = "windows-chrome"
        model.tabs[0].url = "https://account.example.invalid/"
        model.save()
        let restored = BrowserModel(defaults: defaults)
        XCTAssertEqual(restored.active.profileId, BrowserModel.actualProfile)
        XCTAssertEqual(restored.active.url, "https://account.example.invalid/")
        _ = restored.store(for: BrowserModel.actualProfile)
        XCTAssertEqual(defaults.string(forKey: "atma.native.store.actual-device"), identifier)
    }
}
