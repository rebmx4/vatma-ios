import XCTest
@testable import ATMA

@MainActor
final class BrowserPageTranslationTests: XCTestCase {
    func testLanguageDetectionUsesTheDeclaredRegionAndDetectsMissingLanguage() {
        XCTAssertEqual(BrowserPageTranslation.pageLanguage(declared: "pt-BR", sample: "Página inicial"), "pt-BR")
        XCTAssertEqual(BrowserPageTranslation.pageLanguage(declared: "", sample:
            "Benvenuti nella nostra biblioteca. Qui potete leggere i libri più recenti e consultare la nostra collezione digitale."), "it")
    }

    func testTranslationReplacesOnlyCurrentPageTextAndCanRestoreIt() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        let root = try await fixture.start()
        let page = try await fixture.open(root)
        let scriptURL = try XCTUnwrap(Bundle.main.url(forResource: "site-translation", withExtension: "js",
                                                       subdirectory: "BrowserUI/assets"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        let result = try await fixture.script("""
            document.documentElement.lang = 'it';
            document.body.innerHTML =
                '<p id="article">Articolo italiano</p><p id="live">Testo precedente</p>' +
                '<form>Account data <input value="Draft"></form><p translate="no">Keep original</p>' +
                '<p lang="en">Keep this English passage</p>';
            const article = document.getElementById('article');
            const live = document.getElementById('live');
            let clicks = 0;
            article.addEventListener('click', () => clicks++);
            const translator = \(source);
            const sample = translator.languageSample();
            const {texts} = translator.collect('current', 'it');
            live.firstChild.data = 'Updated by site';
            const rejected = translator.apply('previous', ['Статья', 'Старый текст']);
            const applied = translator.apply('current', ['Статья', 'Старый текст']);
            const translated = article.textContent;
            article.click();
            translator.restore();
            return {sample, texts, rejected, applied, translated, original: article.textContent,
                    live: live.textContent, form: document.querySelector('input').value, clicks};
            """, in: page) as? [String: Any]

        XCTAssertEqual(result?["texts"] as? [String], ["Articolo italiano", "Testo precedente"])
        let sample = result?["sample"] as? [String: String]
        XCTAssertEqual(sample?["language"], "it")
        XCTAssertFalse(sample?["sample"]?.contains("Account data") ?? true)
        XCTAssertEqual(result?["rejected"] as? Bool, false)
        XCTAssertEqual(result?["applied"] as? Bool, true)
        XCTAssertEqual(result?["translated"] as? String, "Статья")
        XCTAssertEqual(result?["original"] as? String, "Articolo italiano")
        XCTAssertEqual(result?["live"] as? String, "Updated by site")
        XCTAssertEqual(result?["form"] as? String, "Draft")
        XCTAssertEqual(result?["clicks"] as? Int, 1)
    }
}
