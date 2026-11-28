import XCTest
@testable import ATMA

final class BrowserDownloadTests: XCTestCase {
    @MainActor
    func testDownloadingCurrentAddressLeavesItsTabOpenAndPreservesFileBytes() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        _ = try await fixture.start()
        let resource = "atma-download-" + UUID().uuidString + ".html"
        let body = Data("<!doctype html><title>Download sample</title><p>Keep this tab open.</p>".utf8)
        let server = try BrowserRenderingFixtureServer(resources: ["/" + resource: body])
        defer { server.stop() }
        let url = try await server.start().appendingPathComponent(resource)
        _ = try await fixture.rpc("open", body: ["url": url.absoluteString])
        let page = try XCTUnwrap(fixture.controller.currentRenderer)
        try await fixture.wait("document.title === 'Download sample'", in: page)
        let service = fixture.controller.downloads
        let previousCompletion = service.completionVersion
        _ = try await fixture.rpc("download-current")
        let deadline = Date().addingTimeInterval(12)
        while service.completionVersion == previousCompletion && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertGreaterThan(service.completionVersion, previousCompletion)
        let files = try XCTUnwrap(service.list()["files"] as? [[String: Any]])
        let file = try XCTUnwrap(files.first { $0["name"] as? String == resource })
        let id = try XCTUnwrap(file["id"] as? String)
        let saved = try service.fileURL(id: id)
        defer { try? FileManager.default.removeItem(at: saved) }
        XCTAssertEqual(try Data(contentsOf: saved), body)
        XCTAssertTrue(fixture.controller.currentRenderer === page)
        XCTAssertEqual(page.url, url)
    }

    func testDownloadTerminalStatePreservesTabMetadata() {
        var tab = BrowserTab(profileId: "profile")
        tab.url = "https://a.test/file"; tab.title = "Attachment"
        tab.loading = true; tab.error = "interrupted provisional navigation"
        let id = tab.id
        tab.finishNavigationForDownload()
        XCTAssertFalse(tab.loading)
        XCTAssertNil(tab.error)
        XCTAssertEqual(tab.id, id)
        XCTAssertEqual(tab.profileId, "profile")
        XCTAssertEqual(tab.url, "https://a.test/file")
        XCTAssertEqual(tab.title, "Attachment")
    }

    func testOnlyExpectedNavigationPolicyInterruptionIsSuppressed() {
        let transition = DownloadNavigationTransition(tabID: "tab", url: "https://a.test/file", navigationID: "nav-1")
        let interruption = NSError(domain: "WebKitErrorDomain", code: 102)
        XCTAssertTrue(transition.isExpectedInterruption(interruption, navigationID: "nav-1", failingURL: nil))
        XCTAssertFalse(transition.isExpectedInterruption(interruption, navigationID: "nav-2", failingURL: transition.url))
        XCTAssertFalse(transition.isExpectedInterruption(NSError(domain: "other", code: 102), navigationID: "nav-1", failingURL: nil))
        XCTAssertFalse(transition.isExpectedInterruption(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), navigationID: "nav-1", failingURL: nil))
    }

    func testActionDownloadBeforeNavigationStartRequiresExactFailingURL() {
        let transition = DownloadNavigationTransition(tabID: "tab", url: "https://a.test/file", navigationID: nil)
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertTrue(transition.isExpectedInterruption(cancelled, navigationID: "new-nav", failingURL: transition.url))
        XCTAssertFalse(transition.isExpectedInterruption(cancelled, navigationID: "new-nav", failingURL: "https://b.test/file"))
        XCTAssertFalse(transition.isExpectedInterruption(cancelled, navigationID: nil, failingURL: nil))
    }

    func testUnicodeFilenameAndCollisionSuffixFitByteBudget() {
        let suffix = "12345678-1234-1234-1234-123456789ABC"
        for stem in [String(repeating: "я", count: 300), String(repeating: "👩🏽‍💻", count: 100)] {
            let original = stem + ".mp4"
            let ordinary = DownloadFilename.make(original)
            let collision = DownloadFilename.make(original, suffix: suffix)
            XCTAssertLessThanOrEqual(ordinary.utf8.count, DownloadFilename.maximumBytes)
            XCTAssertLessThanOrEqual(collision.utf8.count, DownloadFilename.maximumBytes)
            XCTAssertTrue(collision.hasSuffix("-" + suffix + ".mp4"))
            XCTAssertTrue(ordinary.hasSuffix(".mp4"))
        }
        XCTAssertLessThanOrEqual(DownloadFilename.make("name." + String(repeating: "界", count: 200), suffix: suffix).utf8.count,
                                 DownloadFilename.maximumBytes)
    }

    func testFilenameCannotAddPathOrHiddenComponents() {
        XCTAssertEqual(DownloadFilename.make("../../.hidden"), "download")
        XCTAssertEqual(DownloadFilename.make("/folder/report.txt"), "report.txt")
        XCTAssertFalse(DownloadFilename.make("a\\b.txt").contains("\\"))
    }
}
