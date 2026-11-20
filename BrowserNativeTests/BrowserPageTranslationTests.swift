import XCTest
@testable import ATMA

@MainActor
final class BrowserPageTranslationTests: XCTestCase {
    func testTranslationReplacesOnlyCurrentPageTextAndCanRestoreIt() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        let page = try await fixture.open(root)
        let scriptURL = try XCTUnwrap(Bundle.main.url(forResource: "site-translation", withExtension: "js",
                                                       subdirectory: "BrowserUI/assets"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        let result = try await fixture.script("""
            document.documentElement.lang = 'en';
            document.body.innerHTML =
                '<p id="article">English article</p><p id="live">Old content</p>' +
                '<form>Account data <input value="Draft"></form><p translate="no">Keep original</p>';
            const article = document.getElementById('article');
            const live = document.getElementById('live');
            let clicks = 0;
            article.addEventListener('click', () => clicks++);
            const translator = \(source);
            const {texts} = translator.collect('current');
            live.firstChild.data = 'Updated by site';
            const rejected = translator.apply('previous', ['Статья', 'Старый текст']);
            const applied = translator.apply('current', ['Статья', 'Старый текст']);
            const translated = article.textContent;
            article.click();
            translator.restore();
            return {texts, rejected, applied, translated, original: article.textContent,
                    live: live.textContent, form: document.querySelector('input').value, clicks};
            """, in: page) as? [String: Any]

        XCTAssertEqual(result?["texts"] as? [String], ["English article", "Old content"])
        XCTAssertEqual(result?["rejected"] as? Bool, false)
        XCTAssertEqual(result?["applied"] as? Bool, true)
        XCTAssertEqual(result?["translated"] as? String, "Статья")
        XCTAssertEqual(result?["original"] as? String, "English article")
        XCTAssertEqual(result?["live"] as? String, "Updated by site")
        XCTAssertEqual(result?["form"] as? String, "Draft")
        XCTAssertEqual(result?["clicks"] as? Int, 1)
    }
}
