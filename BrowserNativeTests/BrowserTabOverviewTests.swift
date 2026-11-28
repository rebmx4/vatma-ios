import XCTest
@testable import ATMA

@MainActor
final class BrowserTabOverviewTests: XCTestCase {
    func testSnapshotPersistsForExactOrdinaryTabAndNeverForPrivateTabs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "https://example.org/folder"))
        let tab = BrowserTab(profileId: BrowserModel.actualProfile, url: url.absoluteString)
        let store = TabPreviewStore(directory: directory)
        let bytes = Data([1, 2, 3])
        store.save(bytes, url: url, for: tab)
        XCTAssertEqual(TabPreviewStore(directory: directory).preview(for: tab)?.source, "data:image/jpeg;base64,AQID")
        var navigated = tab
        navigated.url = "https://example.org/other"
        XCTAssertNil(store.preview(for: navigated))
        for isIncognito in [false, true] {
            var protected = tab
            protected.privateBrowsing = isIncognito
            protected.privateDesktopBrowsing = !isIncognito
            XCTAssertNil(store.preview(for: protected))
            protected.id = UUID().uuidString
            store.save(bytes, url: url, for: protected)
            protected.privateBrowsing = nil
            protected.privateDesktopBrowsing = nil
            XCTAssertNil(store.preview(for: protected))
        }
        store.remove(for: tab.id)
        XCTAssertNil(store.preview(for: tab))
    }

    func testCloseManyKeepsTheOverviewAndOtherGroups() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        _ = try await fixture.start()
        let ordinaryID = fixture.controller.model.activeTabId
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let firstPrivate = fixture.controller.model.activeTabId
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        let secondPrivate = fixture.controller.model.activeTabId
        _ = try await fixture.rpc("panel", body: ["panel": "tabs"])
        _ = try await fixture.rpc("tabs/close-many", body: ["tabIds": [firstPrivate, secondPrivate]])
        XCTAssertEqual(fixture.controller.panel, "tabs")
        XCTAssertEqual(fixture.controller.model.tabs.map(\.id), [ordinaryID])
        XCTAssertEqual(fixture.controller.model.activeTabId, ordinaryID)
    }

    func testOverviewHistoryUsesOpenOrdinaryWebKitPages() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        let ordinaryID = fixture.controller.model.activeTabId
        let ordinary = try await fixture.open(root, path: "a")
        _ = try await fixture.open(root, path: "b")
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        _ = try await fixture.open(root, path: "c")
        _ = try await fixture.rpc("panel", body: ["panel": "tabs"])
        let response = try await fixture.rpc("tabs/history") as? [String: Any]
        let entries = try XCTUnwrap(response?["entries"] as? [[String: String]])
        XCTAssertEqual(entries.compactMap { $0["url"] }, ["b", "a"].map { root.appendingPathComponent($0).absoluteString })
        XCTAssertTrue(entries.allSatisfy { $0["tabId"] == ordinaryID })

        _ = try await fixture.rpc("tabs/history/open", body: [
            "tabId": ordinaryID, "url": root.appendingPathComponent("a").absoluteString
        ])
        XCTAssertTrue(fixture.controller.currentRenderer === ordinary)
        try await fixture.wait("document.title === 'Page-a'", in: ordinary)
    }

    func testPrivatePlusAndDuplicateUseTheSourceSessionFromTheOverview() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        let ordinaryID = fixture.controller.model.activeTabId
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
        _ = try await fixture.rpc("private-device", body: ["profileId": "galaxy-a54", "separateSession": true])
        let source = fixture.controller.model.active
        let original = try await fixture.open(root, path: "a")
        _ = try await fixture.rpc("tabs/select", body: ["tabId": ordinaryID])
        _ = try await fixture.rpc("panel", body: ["panel": "tabs"])
        _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true, "sourceTabId": source.id])
        XCTAssertEqual(fixture.controller.model.active.privateSessionID, source.privateSessionID)
        XCTAssertEqual(fixture.controller.model.active.profileId, "galaxy-a54")

        _ = try await fixture.rpc("panel", body: ["panel": "tabs"])
        _ = try await fixture.rpc("tabs/duplicate", body: ["tabId": source.id])
        let copy = fixture.controller.model.active
        let renderer = try XCTUnwrap(fixture.controller.currentRenderer)
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.privateSessionID, source.privateSessionID)
        XCTAssertEqual(copy.profileId, source.profileId)
        XCTAssertEqual(fixture.controller.panel, "tabs")
        XCTAssertFalse(renderer === original)
        XCTAssertTrue(renderer.configuration.websiteDataStore === original.configuration.websiteDataStore)
    }
}
