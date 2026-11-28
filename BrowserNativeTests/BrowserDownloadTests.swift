import XCTest
@testable import ATMA

final class BrowserDownloadTests: XCTestCase {
    @MainActor
    private func pending(_ service: DownloadService) async throws -> DownloadService.Transfer {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if let task = service.tasks.first(where: { $0.status == "confirm" }) { return task }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw BrowserFailure.invalid("Timed out waiting for a download confirmation.")
    }

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
        _ = try await fixture.rpc("download-current")
        let initial = try await pending(service)
        XCTAssertEqual(initial.expected, Int64(body.count))
        XCTAssertEqual(initial.name, resource)
        XCTAssertFalse(try (service.list()["files"] as? [[String: Any]] ?? []).contains { $0["name"] as? String == resource })
        _ = try await fixture.rpc("download/cancel", body: ["id":initial.id])
        XCTAssertEqual(initial.status, "cancelled")
        _ = try await fixture.rpc("download/retry", body: ["id":initial.id])
        let retry = try await pending(service)
        let previousCompletion = service.completionVersion
        _ = try await fixture.rpc("download/confirm", body: ["id":retry.id])
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
        XCTAssertEqual(service.notice?.fileID, id)
        _ = try await fixture.rpc("panel", body: ["panel":"files"])
        _ = try await fixture.rpc("file/delete", body: ["fileId":id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
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

    @MainActor
    func testNavigatingToGeneratedFileDownloadsBytesWithoutReplacingThePage() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        let page = try await fixture.open(root)
        let pageURL = page.url
        let contents = UUID().uuidString
        let service = fixture.controller.downloads
        let previousVersion = service.completionVersion
        let previous = try XCTUnwrap(service.list()["files"] as? [[String: Any]])
        let oldIDs = Set(previous.compactMap { $0["id"] as? String })
        _ = try await fixture.script("""
            const url = URL.createObjectURL(new Blob([contents], {type:'application/octet-stream'}));
            setTimeout(() => location.assign(url), 0);
            return true;
            """, in: page, arguments: ["contents": contents])
        let task = try await pending(service)
        service.confirm(task.id)
        let deadline = Date().addingTimeInterval(12)
        while service.completionVersion == previousVersion && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let rows = try XCTUnwrap(service.list()["files"] as? [[String: Any]])
        let ids = rows.compactMap { $0["id"] as? String }.filter { !oldIDs.contains($0) }
        XCTAssertEqual(ids.count, 1)
        let savedURL = try service.fileURL(id: XCTUnwrap(ids.first))
        defer { try? FileManager.default.removeItem(at: savedURL) }
        XCTAssertEqual(try Data(contentsOf: savedURL), Data(contents.utf8))
        XCTAssertEqual(page.url, pageURL)
    }

    @MainActor
    func testRepeatedDownloadsKeepBothFilesAndLargeVideoCanBeSavedToPhotos() throws {
        let service = DownloadService()
        let name = "ATMA-" + UUID().uuidString + ".mp4"
        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let large = Data(repeating: 42, count: 8 * 1024 * 1024 + 1)
        try large.write(to: first)
        try Data([1, 2, 3]).write(to: second)
        let saved = try service.publishFile(first, suggestedFilename: name)
        defer { try? FileManager.default.removeItem(at: saved) }
        let duplicate = try service.publishFile(second, suggestedFilename: name)
        defer { try? FileManager.default.removeItem(at: duplicate) }
        XCTAssertNotEqual(saved, duplicate)
        XCTAssertEqual(try Data(contentsOf: saved), large)
        XCTAssertEqual(try Data(contentsOf: duplicate), Data([1, 2, 3]))
        let rows = try XCTUnwrap(service.list()["files"] as? [[String: Any]])
        let id = try XCTUnwrap(rows.first { $0["name"] as? String == name }?["id"] as? String)
        let preview = try service.preview(id: id)
        XCTAssertNil(preview["base64"])
        XCTAssertEqual(preview["canSaveToPhotos"] as? Bool, true)
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
