import XCTest
import UIKit
import WebKit
@testable import ATMA

@MainActor
private final class HeldPreviewWebView: WKWebView {
    let previewURL = URL(string: "https://example.invalid/preview")!
    typealias SnapshotReply = @MainActor @Sendable (UIImage?, (any Error)?) -> Void
    var replies: [SnapshotReply] = []
    override var url: URL? { previewURL }
    override func takeSnapshot(with configuration: WKSnapshotConfiguration?, completionHandler: @escaping @MainActor @Sendable (UIImage?, (any Error)?) -> Void) {
        replies.append(completionHandler)
    }
}

@MainActor
final class BrowserPreviewCompletionTests: XCTestCase {
    private var controller: BrowserController!
    private var window: UIWindow!
    private var page: HeldPreviewWebView!
    private var suite: String!
    private var preferences: UserDefaults!
    private var savedPort: Any?

    override func setUpWithError() throws {
        suite = "atma.tests.preview-completion." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        savedPort = UserDefaults.standard.object(forKey: "atma.ui.loopback.port")
        UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port")
        controller = BrowserController(model: BrowserModel(defaults: preferences))
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        page = HeldPreviewWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 400), configuration: WKWebViewConfiguration())
        controller.view.addSubview(page)
        controller.model.tabs[0].url = page.previewURL.absoluteString
        controller.renderers[controller.model.activeTabId] = page
        controller.mode = "browse"
    }

    override func tearDownWithError() throws {
        page.replies.removeAll()
        controller.ui.stopLoading()
        controller.ui.configuration.userContentController.removeScriptMessageHandler(forName: "atma", contentWorld: .page)
        window.isHidden = true
        window.rootViewController = nil
        controller = nil; window = nil; page = nil
        if let savedPort { UserDefaults.standard.set(savedPort, forKey: "atma.ui.loopback.port") }
        else { UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port") }
        preferences.removePersistentDomain(forName: suite)
        preferences = nil
    }

    func testMissingSnapshotReplyReleasesAllWaitingTransitions() async throws {
        let returned = expectation(description: "Optional preview must not block navigation")
        returned.expectedFulfillmentCount = 2
        var calls = 0
        for _ in 0..<2 {
            controller.captureCurrentPreview { calls += 1; returned.fulfill() }
        }
        XCTAssertEqual(page.replies.count, 1, "Waiting transitions must share the same capture")
        await fulfillment(of: [returned], timeout: 3)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(controller.previewCaptures.isEmpty)
        XCTAssertTrue(controller.tabPreviews.isEmpty)
        page.replies[0](image(.red), nil)
        XCTAssertEqual(calls, 2, "A late reply must not repeat navigation")
        XCTAssertTrue(controller.tabPreviews.isEmpty, "An expired reply must not create a stale preview")
    }

    func testExpiredReplyCannotFinishOrReplaceANewerCapture() async throws {
        let first = expectation(description: "First capture expires")
        controller.captureCurrentPreview { first.fulfill() }
        await fulfillment(of: [first], timeout: 3)
        let id = controller.model.activeTabId
        var newCalls = 0
        controller.captureCurrentPreview { newCalls += 1 }
        let pending = try XCTUnwrap(controller.previewCaptures[id])
        XCTAssertEqual(page.replies.count, 2)
        page.replies[0](image(.red), nil)
        XCTAssertTrue(controller.previewCaptures[id] === pending)
        XCTAssertEqual(newCalls, 0)
        XCTAssertNil(controller.tabPreviews[id])
        page.replies[1](image(.blue), nil)
        XCTAssertEqual(newCalls, 1)
        XCTAssertNil(controller.previewCaptures[id])
        XCTAssertEqual(controller.tabPreviews[id]?.url, page.previewURL)
    }

    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }
}
