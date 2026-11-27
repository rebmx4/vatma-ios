import XCTest
import UIKit

/// Copy to BrowserNativeUITests in a capture-only worktree based on the verified release revision.
final class StoreFeatureScreenshotsTests: XCTestCase {
    private let app = XCUIApplication()

    private struct Market {
        let region: String
        let language: String
        let locale: String
    }

    private enum Text: Int {
        case menu, settings, media, audio, vault, pin, incognito, device, chooser
    }

    private struct MissingScene: Error, CustomStringConvertible {
        let description: String
    }

    private let markets = [
        Market(region: "RU", language: "ru", locale: "ru_RU"),
        Market(region: "US", language: "en", locale: "en_US"),
        Market(region: "DE", language: "de", locale: "de_DE"),
        Market(region: "FR", language: "fr", locale: "fr_FR"),
        Market(region: "BR", language: "pt-BR", locale: "pt_BR"),
        Market(region: "PT", language: "pt-BR", locale: "pt_PT"),
        Market(region: "JP", language: "ja", locale: "ja_JP"),
        Market(region: "CN", language: "zh-Hans", locale: "zh_Hans_CN"),
        Market(region: "KR", language: "ko", locale: "ko_KR"),
        Market(region: "ES", language: "es", locale: "es_ES"),
        Market(region: "IT", language: "it", locale: "it_IT"),
    ]

    // Field order matches Text. These strings come from build 14 BrowserUI/assets/i18n.js.
    private let copy = [
        "ru": ["Меню браузера", "Настройки", "Медиаплеер", "Звук в фоне", "Приватный стол", "Код из 6 цифр", "Открыть Инкогнито", "Выбрать устройство для инкогнито", "Устройство инкогнито"],
        "en": ["Browser menu", "Settings", "Media player", "Background audio", "Private desktop", "6-digit code", "Open Incognito", "Choose Incognito device", "Incognito device"],
        "de": ["Browsermenü", "Einstellungen", "Mediaplayer", "Hintergrund-Audio", "Privater Startbereich", "6-stelliger Code", "Inkognito öffnen", "Gerät für Inkognito auswählen", "Inkognitogerät"],
        "fr": ["Menu du navigateur", "Réglages", "Lecteur multimédia", "Audio en arrière-plan", "Accueil privé", "Code à 6 chiffres", "Ouvrir en privé", "Choisir un appareil pour la navigation privée", "Appareil en mode privé"],
        "pt-BR": ["Menu do navegador", "Configurações", "Reprodutor de mídia", "Áudio em segundo plano", "Área inicial privada", "Código de 6 dígitos", "Abrir no modo anônimo", "Escolha um dispositivo para o modo anônimo", "Dispositivo no modo anônimo"],
        "ja": ["ブラウザメニュー", "設定", "メディアプレーヤー", "バックグラウンド再生", "プライベートホーム", "6桁のコード", "シークレットを開く", "シークレットのデバイスを選択", "シークレットのデバイス"],
        "zh-Hans": ["浏览器菜单", "设置", "媒体播放器", "后台音频", "私密桌面", "六位数密码", "打开无痕浏览", "选择无痕浏览设备", "无痕浏览设备"],
        "ko": ["브라우저 메뉴", "설정", "미디어 플레이어", "백그라운드 오디오", "비공개 홈 화면", "6자리 암호", "시크릿 모드 열기", "시크릿 모드 기기 선택", "시크릿 모드 기기"],
        "es": ["Menú del navegador", "Ajustes", "Reproductor multimedia", "Audio en segundo plano", "Inicio privado", "Código de 6 dígitos", "Abrir en incógnito", "Elegir dispositivo para incógnito", "Dispositivo en incógnito"],
        "it": ["Menu del browser", "Impostazioni", "Lettore multimediale", "Audio in background", "Home privata", "Codice a 6 cifre", "Apri in incognito", "Scegli un dispositivo per la navigazione in incognito", "Dispositivo in incognito"],
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testCaptureAllFeaturePanels() {
        var failures: [String] = []
        for market in markets {
            for (name, scenario) in [("media", captureMedia), ("vault", captureVault), ("incognito", captureIncognito)] {
                XCTContext.runActivity(named: "\(market.region) · \(name)") { activity in
                    if app.state != .notRunning { app.terminate() }
                    app.launchArguments = ["-AppleLanguages", "(\(market.language))", "-AppleLocale", market.locale]
                    app.launch()
                    do {
                        let scene = try scenario(market)
                        let attachment = XCTAttachment(screenshot: app.screenshot())
                        attachment.name = "native-14-\(market.region)-\(scene)"
                        attachment.lifetime = .keepAlways
                        activity.add(attachment)
                    } catch {
                        let failure = "\(market.region) · \(name) · \(error)"
                        failures.append(failure)
                        let evidence = XCTAttachment(string: failure)
                        evidence.name = "missing-native-14-\(market.region)-\(name)"
                        evidence.lifetime = .keepAlways
                        activity.add(evidence)
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func captureMedia(_ market: Market) throws -> String {
        try openSettings(market)
        try tap(.media, market)
        let audio = app.descendants(matching: .any).matching(label(.audio, market)).firstMatch
        guard audio.waitForExistence(timeout: 12) else { throw MissingScene(description: "Background audio control") }
        return "media-settings"
    }

    private func captureVault(_ market: Market) throws -> String {
        try openSettings(market)
        try tap(.vault, market)
        let code = app.buttons.matching(label(.pin, market)).firstMatch
        guard code.waitForExistence(timeout: 12) else { throw MissingScene(description: "Fresh private desktop options") }
        return app.buttons["Face ID"].exists ? "face-id-choice" : "pin-choice"
    }

    private func captureIncognito(_ market: Market) throws -> String {
        try openSettings(market)
        try tap(.incognito, market)
        try tap(.device, market)
        let chooser = app.staticTexts.matching(label(.chooser, market)).firstMatch
        guard chooser.waitForExistence(timeout: 12) else { throw MissingScene(description: "Incognito device chooser") }
        return "incognito-chooser"
    }

    private func openSettings(_ market: Market) throws {
        try tap(.menu, market, timeout: 55)
        try tap(.settings, market)
    }

    private func tap(_ field: Text, _ market: Market, timeout: TimeInterval = 12) throws {
        let element = app.buttons.matching(label(field, market)).firstMatch
        guard element.waitForExistence(timeout: timeout) else { throw MissingScene(description: "Missing button \(field)") }
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        guard element.isHittable else { throw MissingScene(description: "Hidden button \(field)") }
        element.tap()
    }

    private func label(_ field: Text, _ market: Market) -> NSPredicate {
        let titles = [copy[market.language]![field.rawValue], copy["ru"]![field.rawValue], copy["en"]![field.rawValue]]
        return NSPredicate(format: "label IN %@", titles)
    }
}
