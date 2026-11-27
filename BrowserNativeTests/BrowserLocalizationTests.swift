import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserLocalizationTests: XCTestCase {
    func testNewInterfaceLanguagesCanBeSelectedAndPersist() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        _ = try await fixture.start()
        let ui = try XCTUnwrap(fixture.controller.ui)
        _ = try await fixture.rpc("panel", body: ["panel": "settings"])
        try await fixture.wait("!!document.getElementById('interface-language')", in: ui)

        for (locale, home) in [("zh-Hans", "首页"), ("ko", "홈"), ("ja", "ホーム")] {
            let selected = try await fixture.script("""
                const select = document.getElementById('interface-language');
                select.value = locale;
                select.dispatchEvent(new Event('change', {bubbles:true}));
                await Promise.resolve();
                return document.documentElement.lang === locale &&
                    document.getElementById('go-home').getAttribute('aria-label') === home &&
                    localStorage.getItem('atma-interface-language') === locale;
                """, in: ui, arguments: ["locale": locale, "home": home]) as? Bool
            XCTAssertEqual(selected, true, "ATMA should switch and save \(locale)")
        }

        ui.reload()
        try await fixture.wait("!!document.body.dataset.mode && document.documentElement.lang === 'ja'", in: ui)
    }
}
