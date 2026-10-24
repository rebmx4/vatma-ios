import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserShortcutProfileTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var model: BrowserModel!

    override func setUp() {
        super.setUp()
        suite = "atma.tests.shortcut-profile." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        model = BrowserModel(defaults: defaults)
    }

    override func tearDown() {
        model = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testLegacyShortcutReusesAnExistingCookieStoreAfterTheGlobalModelChanges() async throws {
        let profile = "iphone-13-pro-max"
        let store = model.store(for: profile)
        try await addCookie(to: store, value: "retained-login")
        model.tabs[model.activeIndex].profileId = BrowserModel.actualProfile
        let resolved = try await model.shortcutProfile(for: "https://account.example.invalid/inbox")
        XCTAssertEqual(resolved, profile)
        XCTAssertTrue(model.store(for: resolved) === store)
        let cookies = await cookies(in: store)
        XCTAssertEqual(cookies.first { $0.name == "session" }?.value, "retained-login")
    }

    func testLegacyShortcutCanRecoverItsProfileFromTheExistingWebsiteTab() async throws {
        model.tabs[0].url = "https://account.example.invalid/inbox"
        model.tabs[0].profileId = "iphone-13-pro-max"
        let other = BrowserTab(profileId: BrowserModel.actualProfile)
        model.tabs.append(other); model.activeTabId = other.id
        let resolved = try await model.shortcutProfile(for: "https://account.example.invalid/")
        XCTAssertEqual(resolved, "iphone-13-pro-max")
    }

    func testMultipleStoredAccountsAreNotChosenArbitrarily() async throws {
        try await addCookie(to: model.store(for: BrowserModel.actualProfile), value: "account-one")
        try await addCookie(to: model.store(for: "iphone-13-pro-max"), value: "account-two")
        model.tabs[0].profileId = "windows-chrome"
        do {
            _ = try await model.shortcutProfile(for: "https://account.example.invalid/")
            XCTFail("Ambiguous stored accounts must not be opened arbitrarily")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("несколько профилей"))
        }
    }

    func testUnvisitedLegacyShortcutUsesAStableActualDeviceAndRejectsUnsafeURLs() async throws {
        model.tabs[0].profileId = "windows-chrome"
        let resolved = try await model.shortcutProfile(for: "https://unvisited.example.invalid/")
        XCTAssertEqual(resolved, BrowserModel.actualProfile)
        do {
            _ = try await model.shortcutProfile(for: "file:///private")
            XCTFail("Shortcut profile lookup must reject local URLs")
        } catch {}
    }

    private func addCookie(to store: WKWebsiteDataStore, value: String) async throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "account.example.invalid", .path: "/", .name: "session", .value: value, .secure: "TRUE"]))
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
    }

    private func cookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
