import XCTest
import UIKit

final class BrowserPrivacyUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "--atma-ui-diagnostics"]
        app.launch()
        XCTAssertTrue(button(["Рабочий стол", "Home"]).waitForExistence(timeout: 20))
    }

    func testIncognitoDesktopIconAndWhiteSearchScreen() throws {
        let incognito = button(["Открыть Инкогнито", "Open Incognito"])
        XCTAssertTrue(incognito.waitForExistence(timeout: 10)); incognito.tap()
        let input = app.textFields.matching(NSPredicate(format: "label IN %@", ["Поиск или адрес в инкогнито", "Search or address in Incognito"])).firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10)); XCTAssertTrue(input.isHittable)
        screenshot("incognito-start")
        button(["Рабочий стол", "Home"]).tap()
        XCTAssertTrue(button(["Открыть ВКонтакте", "Open ВКонтакте"]).waitForExistence(timeout: 10))
        XCTAssertFalse(input.isHittable)
    }

    func testEmptySpaceAndNewWebsiteIconEnterEditingWithoutAnImageMenu() throws {
        let ui = app.webViews.matching(identifier: "atma.ui").firstMatch
        ui.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.25)).press(forDuration: 4)
        let ordinaryRemove = button(["Удалить ВКонтакте", "Remove ВКонтакте"])
        XCTAssertTrue(ordinaryRemove.waitForExistence(timeout: 5))
        ui.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.25)).tap()
        XCTAssertTrue(ordinaryRemove.waitForNonExistence(timeout: 5))
        button(["Настройки", "Settings"]).tap()
        let add = button(["Добавить веб-приложение", "Add web app"])
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let name = app.textFields.matching(NSPredicate(format: "label IN %@", ["Название приложения", "App name"])).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Gesture fixture")
        let url = app.textFields.matching(NSPredicate(format: "label IN %@", ["Адрес приложения", "App address"])).firstMatch
        url.tap(); url.typeText("https://www.apple.com/")
        button(["Добавить на рабочий стол", "Add to home"]).tap()
        let shortcut = button(["Открыть Gesture fixture", "Open Gesture fixture"])
        XCTAssertTrue(shortcut.waitForExistence(timeout: 30))
        let address = app.textFields.matching(NSPredicate(format: "label IN %@", ["Приложения, поисковый запрос или адрес сайта", "Apps, search query or website address"])).firstMatch
        address.tap(); address.typeText("Gesture fixture")
        XCTAssertTrue(shortcut.isHittable); shortcut.press(forDuration: 4)
        let remove = button(["Удалить Gesture fixture", "Remove Gesture fixture"])
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertFalse(button(["Сохранить изображение", "Сохранить фото", "Добавить в Фото", "Save Image", "Save to Photos", "Add to Photos"]).exists)
        remove.tap()
        XCTAssertFalse(button(["Сохранить", "Save"]).exists, "The remove control must not open the shortcut editor")
        ui.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.25)).tap()
        address.tap(); address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Gesture fixture".count))
    }

    private func button(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
