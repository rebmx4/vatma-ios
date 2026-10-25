import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserPrivacyTests: XCTestCase {
    private func privateTab() throws -> BrowserTab {
        let data = Data(#"{"id":"private-fixture","profileId":"actual-device","url":"https://private.example/secret","title":"Private fixture","siteName":"private.example","iconUrl":"","loading":false,"privateBrowsing":true}"#.utf8)
        return try JSONDecoder().decode(BrowserTab.self, from: data)
    }

    private func preferences() throws -> (UserDefaults, String) {
        let suite = "atma.tests.privacy." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testPrivateAddressesAndIdentityNeverEnterTheRestoredSession() throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(defaults: defaults)
        let regular = BrowserTab(profileId: BrowserModel.actualProfile, url: "https://ordinary.example/")
        let hidden = try privateTab()
        model.tabs = [regular, hidden]; model.activeTabId = hidden.id
        model.save()
        let saved = try XCTUnwrap(defaults.data(forKey: "atma.native.session.v1"))
        let text = try XCTUnwrap(String(data: saved, encoding: .utf8))
        XCTAssertFalse(text.contains("private.example"), "Private addresses must not be written to session storage")
        XCTAssertFalse(text.contains(hidden.id), "The active private tab ID must not leak into persistent state")
        let restored = BrowserModel(defaults: defaults)
        XCTAssertEqual(restored.tabs.map(\.id), [regular.id])
        XCTAssertEqual(restored.activeTabId, regular.id)
    }

    func testPrivateOnlySessionRestoresOneOrdinaryBlankTab() throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(defaults: defaults)
        let hidden = try privateTab()
        model.tabs = [hidden]; model.activeTabId = hidden.id; model.save()
        let restored = BrowserModel(defaults: defaults)
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.active.url, "")
        XCTAssertNotEqual(restored.activeTabId, hidden.id)
    }

    func testPrivateWebsiteRendererNeverUsesTheOrdinaryPersistentStore() throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let controller = fixture.controller
        let regular = controller.renderer(for: controller.model.active)
        let hidden = controller.renderer(for: try privateTab())
        XCTAssertTrue(regular.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(hidden.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(regular.configuration.websiteDataStore === hidden.configuration.websiteDataStore)
    }

    func testStateExposesPrivateModeAndUnavailableHistoryOnABlankTab() throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(defaults: defaults)
        model.tabs = [try privateTab()]; model.activeTabId = model.tabs[0].id
        let state = BrowserController(model: model).state()
        XCTAssertEqual(state["privateBrowsing"] as? Bool, true)
        XCTAssertEqual(state["canGoBack"] as? Bool, false)
        XCTAssertEqual(state["canGoForward"] as? Bool, false)
    }
}
