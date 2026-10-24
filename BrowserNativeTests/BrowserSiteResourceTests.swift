import Foundation
import XCTest
@testable import ATMA

@MainActor
final class BrowserSiteResourceTests: XCTestCase {
    func testLargeHTMLPrefixPreservesUnicodeIconURLAtUTF8Boundary() async throws {
        let limit = 524_288
        let head = Data("<!doctype html><html><head><link rel='apple-touch-icon' href='/иконка.png'></head><body>".utf8)
        let page = head + Data(repeating: 120, count: limit - head.count - 1) + Data("€rest of body".utf8)
        let fixture = try BrowserRenderingFixtureServer(resources: ["/large": page])
        defer { fixture.stop() }
        let base = try await fixture.start()
        let result = try await BrowserSiteResource.load(base.appendingPathComponent("large").absoluteString, kind: "document")
        let text = try XCTUnwrap(result["text"] as? String)
        XCTAssertTrue(text.contains("href='/иконка.png'"), "A partial UTF-8 character in the body must not corrupt the icon URL in the head")
        XCTAssertLessThanOrEqual(text.lengthOfBytes(using: .utf8), limit)
    }

    func testMetadataPrefixExceptionDoesNotAllowOversizedImagesOrManifests() async throws {
        let fixture = try BrowserRenderingFixtureServer(resources: [
            "/large.png": Data(repeating: 120, count: 1_048_577),
            "/large.json": Data(repeating: 120, count: 131_073),
        ])
        defer { fixture.stop() }
        let base = try await fixture.start()
        for (path, kind) in [("large.png", "image"), ("large.json", "manifest")] {
            do {
                _ = try await BrowserSiteResource.load(base.appendingPathComponent(path).absoluteString, kind: kind)
                XCTFail("Oversized \(kind) must still be rejected")
            } catch {
                XCTAssertTrue(error is BrowserFailure, "Expected the resource size policy to reject the response, not a network failure: \(error)")
            }
        }
    }
}
