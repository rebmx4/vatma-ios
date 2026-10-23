import XCTest
@testable import ATMA

final class BrowserDownloadTests: XCTestCase {
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

    func testBlockerExclusionIsExactHostAndDoesNotFollowRedirect() {
        let disabled: Set<String> = ["a.example"]
        XCTAssertFalse(HostBlockerPolicy.enabled(host: "A.EXAMPLE", disabledHosts: disabled))
        XCTAssertTrue(HostBlockerPolicy.enabled(host: "b.example", disabledHosts: disabled))
        XCTAssertTrue(HostBlockerPolicy.enabled(host: "sub.a.example", disabledHosts: disabled))
        XCTAssertTrue(HostBlockerPolicy.enabled(host: nil, disabledHosts: disabled))
    }
}
