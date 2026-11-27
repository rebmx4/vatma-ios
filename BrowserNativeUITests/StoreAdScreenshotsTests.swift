import XCTest
import WebKit
import UIKit

/// Capture-only test. Uses the same owned page in neutral WKWebView and release ATMA.
final class StoreAdScreenshotsTests: XCTestCase {
    private struct Market {
        let region, language, locale, menu, tab, go, title, confirmed: String

        init(_ region: String, _ language: String, _ locale: String, _ menu: String, _ tab: String,
             _ go: String, _ title: String, _ confirmed: String) {
            self.region = region; self.language = language; self.locale = locale; self.menu = menu
            self.tab = tab; self.go = go; self.title = title; self.confirmed = confirmed
        }
    }

    private let markets = [
        Market("RU", "ru", "ru_RU", "Меню браузера", "Новая вкладка", "Перейти", "Проверка фильтра", "Рекламный запрос не загрузился"),
        Market("US", "en", "en_US", "Browser menu", "New tab", "Go", "Filter test", "Advertising request did not load"),
        Market("DE", "de", "de_DE", "Browsermenü", "Neuer Tab", "Los", "Filtertest", "Werbeanfrage wurde nicht geladen"),
        Market("FR", "fr", "fr_FR", "Menu du navigateur", "Nouvel onglet", "Aller", "Test de filtrage", "La requête publicitaire a échoué"),
        Market("BR", "pt-BR", "pt_BR", "Menu do navegador", "Nova guia", "Ir", "Teste do filtro", "A solicitação de anúncio não carregou"),
        Market("PT", "pt-BR", "pt_PT", "Menu do navegador", "Nova guia", "Ir", "Teste do filtro", "O pedido publicitário não foi carregado"),
        Market("JP", "ja", "ja_JP", "ブラウザメニュー", "新規タブ", "移動", "フィルターのテスト", "広告リクエストを読み込めませんでした"),
        Market("CN", "zh-Hans", "zh_Hans_CN", "浏览器菜单", "新建标签页", "前往", "广告过滤测试", "广告请求未加载"),
        Market("KR", "ko", "ko_KR", "브라우저 메뉴", "새 탭", "이동", "광고 필터 테스트", "광고 요청이 로드되지 않았습니다"),
        Market("ES", "es", "es_ES", "Menú del navegador", "Nueva pestaña", "Ir", "Prueba del filtro", "No se cargó la solicitud publicitaria"),
        Market("IT", "it", "it_IT", "Menu del browser", "Nuova scheda", "Vai", "Test del filtro", "La richiesta pubblicitaria non è stata caricata"),
    ]

    private let filmTitles = [
        "RU":"Над облаками", "US":"Above the clouds", "DE":"Über den Wolken", "FR":"Au-dessus des nuages",
        "BR":"Acima das nuvens", "PT":"Acima das nuvens", "JP":"雲の上で", "CN":"云海之上", "KR":"구름 위에서",
        "ES":"Sobre las nubes", "IT":"Sopra le nuvole",
    ]

    private struct MissingShot: Error, CustomStringConvertible { let description: String }
    private let app = XCUIApplication()

    @MainActor
    func testCaptureAcrossMarketsWhenSameURLControlSucceeds() async throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        var resources = Dictionary(uniqueKeysWithValues: markets.map {
            ("/\($0.region).html", Data(demoPage($0).utf8))
        })
        resources["/alive.json"] = Data("{\"control\":true}".utf8)
        let bundle = Bundle(for: Self.self)
        resources["/film.jpg"] = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "StoreFilterPoster", withExtension: "jpg")))
        resources["/film.mp4"] = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "StoreFilterFilm", withExtension: "mp4")))
        let server = try BrowserRenderingFixtureServer(resources: resources)
        defer { server.stop() }
        let root = try await server.start()
        var failures: [String] = []
        for market in markets {
            let address = root.appendingPathComponent(market.region + ".html")
            if app.state != .notRunning { app.terminate() }
            do {
                try await verifyUnfilteredControl(address)
                app.launchArguments = ["-AppleLanguages", "(\(market.language))", "-AppleLocale", market.locale]
                app.launch()
                try openAddress(address, market)
                let result = app.staticTexts[market.confirmed].firstMatch
                guard result.waitForExistence(timeout: 20), result.isHittable else {
                    throw MissingShot(description: "The production browser did not display the filtered outcome")
                }
                let screenshot = app.screenshot()
                app.terminate()
                try await verifyUnfilteredControl(address)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "native-14-\(market.region)-ad-blocking"
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch {
                let failure = "\(market.region): \(error)"
                failures.append(failure)
                let diagnostic = XCTAttachment(string: failure)
                diagnostic.name = "missing-native-14-\(market.region)-ad-blocking"
                diagnostic.lifetime = .keepAlways
                add(diagnostic)
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    @MainActor
    private func verifyUnfilteredControl(_ address: URL) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let reference = WKWebView(frame: CGRect(x: 0, y: 0, width: 430, height: 880), configuration: configuration)
        reference.load(URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData))
        defer { reference.stopLoading() }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let result = (try? await reference.evaluateJavaScript("window.atmaDemoOutcome || ''")) as? String
            if result == "control-ok" { return }
            if result == "request-failed" || result == "network-unavailable" { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw MissingShot(description: "The same URL failed in the unfiltered control")
    }

    private func openAddress(_ address: URL, _ market: Market) throws {
        try tap([market.menu, "Меню браузера", "Browser menu"], timeout: 55)
        try tap([market.tab, "Новая вкладка", "New tab"])
        let field = app.webViews.matching(identifier: "atma.ui").firstMatch.textFields.firstMatch
        guard field.waitForExistence(timeout: 12), field.isHittable else { throw MissingShot(description: "Missing address field") }
        field.tap()
        field.typeText(address.absoluteString)
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.value as? String == address.absoluteString }, object: nil)
        guard XCTWaiter.wait(for: [entered], timeout: 8) == .completed else { throw MissingShot(description: "Address field did not retain the complete URL") }
        try tap([market.go, "Перейти", "Go"])
    }

    private func tap(_ labels: [String], timeout: TimeInterval = 12) throws {
        let element = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        guard element.waitForExistence(timeout: timeout), element.isHittable else { throw MissingShot(description: "Missing control: \(labels[0])") }
        element.tap()
    }

    private func demoPage(_ market: Market) -> String {
        """
        <!doctype html><html lang="\(market.language)"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>ATMA · \(filmTitles[market.region]!)</title><style>
        *{box-sizing:border-box}body{margin:0;background:#fff4ed;color:#29151d;font:17px system-ui,sans-serif}
        main{max-width:900px;margin:auto;padding:32px max(22px,5vw)}small{font-weight:800;letter-spacing:.14em}
        h1{font-size:clamp(32px,6vw,72px);line-height:1.04;margin:27px 0 19px}
        video{width:100%;height:clamp(200px,62vw,435px);object-fit:cover;border-radius:22px;background:#29151d;display:block}
        p{font-size:clamp(19px,3.5vw,34px);font-weight:700;margin:26px 0;color:#5e272f}
        </style><main><small>ATMA STUDIO</small><h1>\(filmTitles[market.region]!)</h1><video controls playsinline preload="none" poster="/film.jpg"><source src="/film.mp4" type="video/mp4"></video>
        <p id="outcome" role="status"></p></main>
        <script>
        (async () => {
          const status=document.getElementById('outcome');
          const abort=new AbortController(), timer=setTimeout(()=>abort.abort(),7000);
          const options={credentials:'omit',referrerPolicy:'no-referrer',cache:'no-store',signal:abort.signal};
          try {
            const local=await fetch('/alive.json',options);
            if (!local.ok || !(await local.json()).control) throw Error('Local control failed');
            try {
              await fetch('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js',{...options,mode:'no-cors'});
              window.atmaDemoOutcome='control-ok';
            } catch (error) {
              if (error.name==='AbortError') throw error;
              window.atmaDemoOutcome='request-failed';
              status.textContent='\(market.confirmed)';
            }
          } catch { window.atmaDemoOutcome='network-unavailable'; }
          finally { clearTimeout(timer); }
        })();
        </script></html>
        """
    }
}
