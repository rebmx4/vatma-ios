import XCTest
import UIKit

final class BrowserPrivacyUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "--atma-ui-diagnostics"]
        app.launch()
        XCTAssertTrue(button(["Рабочий стол", "Home"]).waitForExistence(timeout: 60))
    }

    func testIncognitoDesktopIconOpensWhiteSearchScreen() throws {
        let incognito = button(["Открыть Инкогнито", "Open Incognito"])
        XCTAssertTrue(incognito.waitForExistence(timeout: 10)); incognito.tap()
        let input = app.textFields.matching(NSPredicate(format: "label IN %@", ["Поиск или адрес в инкогнито", "Search or address in Incognito"])).firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10)); XCTAssertTrue(input.isHittable)
        let home = button(["Рабочий стол", "Home"])
        XCTAssertTrue(home.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Incognito start must not focus the search field automatically")
        XCTAssertGreaterThan(home.frame.minY, input.frame.maxY)
        XCTAssertLessThanOrEqual(home.frame.minY - input.frame.maxY, 48, "Incognito input belongs just above browser navigation")
        input.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        let device = button(["Выбрать устройство для инкогнито", "Choose device for Incognito"])
        XCTAssertTrue(device.isHittable)
        XCTAssertLessThanOrEqual(device.frame.maxY, input.frame.minY, "Device choice belongs above the Incognito address field")
        let ui = app.webViews.matching(identifier: "atma.ui").firstMatch
        XCTAssertTrue(ui.exists)
        let nativeInputTop = ui.frame.maxY
        XCTAssertGreaterThanOrEqual(nativeInputTop - input.frame.maxY, 0)
        XCTAssertLessThanOrEqual(nativeInputTop - input.frame.maxY, 24, "Incognito input must sit above the system keyboard region")
        XCTAssertGreaterThanOrEqual(keyboard.frame.minY - nativeInputTop, 0)
        XCTAssertLessThanOrEqual(keyboard.frame.minY - nativeInputTop, 140, "Only the system input accessory and prediction row may separate the field from the keys")
        XCTAssertFalse(home.isHittable, "Browser navigation hides during Incognito address entry")
        screenshot("incognito-start")
        input.typeText("example.org")
        XCTAssertEqual(input.value as? String, "example.org")
        device.tap()
        let close = button(["Закрыть", "Close"])
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let navigationReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in home.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [navigationReady], timeout: 5), .completed)
        input.tap()
        button(["Перейти в инкогнито", "Go in Incognito"]).tap()
        let website = app.webViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "atma.site.")).firstMatch
        XCTAssertTrue(website.waitForExistence(timeout: 10), "Private address submission must create a site renderer")
        let browserNavigationReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in home.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [browserNavigationReady], timeout: 5), .completed)
        home.tap()
        XCTAssertTrue(button(["Открыть ВКонтакте", "Open ВКонтакте"]).waitForExistence(timeout: 10))
        XCTAssertFalse(input.isHittable)
    }

    func testEmptySpaceAndNewWebsiteIconEnterEditingWithoutAnImageMenu() throws {
        let ui = app.webViews.matching(identifier: "atma.ui").firstMatch
        // Keep the gesture inside Home on wide iPads, away from icons and scrollbars.
        let emptySpace = ui.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        emptySpace.press(forDuration: 4)
        let ordinaryRemove = button(["Удалить ВКонтакте", "Remove ВКонтакте"])
        XCTAssertTrue(ordinaryRemove.waitForExistence(timeout: 5))
        emptySpace.tap()
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
        emptySpace.tap()
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
