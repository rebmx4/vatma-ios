import XCTest
import UIKit

final class BrowserPrivacyUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // Keep the Russian desktop separate from the unit-test host's saved regional layout.
        app.launchArguments = ["-atma.ui.loopback.port", "28917", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "--atma-ui-diagnostics"]
        app.launch()
        XCTAssertTrue(button(["Меню браузера", "Browser menu"]).waitForExistence(timeout: 60))
    }

    func testIncognitoDesktopIconOpensPrivateSearchScreen() throws {
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
        let addressEntered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            input.value as? String == "example.org"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [addressEntered], timeout: 5), .completed,
                       "The Incognito address must contain the complete URL, got \(String(describing: input.value))")
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
        let incognito = button(["Открыть Инкогнито", "Open Incognito"])
        let dockShortcut = button(["Открыть YouTube", "Open YouTube"])
        let desktopReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            incognito.isHittable && dockShortcut.isHittable && dockShortcut.frame.minY > incognito.frame.maxY + 60
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [desktopReady], timeout: 10), .completed)
        let emptyY = (incognito.frame.maxY + dockShortcut.frame.minY) / 2
        let emptySpace = ui.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: ui.frame.width / 2, dy: emptyY - ui.frame.minY)
        )
        emptySpace.press(forDuration: 4)
        let ordinaryRemove = button(["Удалить ВКонтакте", "Remove ВКонтакте"])
        let editingEntered = ordinaryRemove.waitForExistence(timeout: 5)
        if !editingEntered { screenshot("desktop-edit-long-press-failure") }
        XCTAssertTrue(editingEntered)
        emptySpace.tap()
        XCTAssertTrue(ordinaryRemove.waitForNonExistence(timeout: 5))
        let vkButtons = app.buttons.matching(NSPredicate(format: "label IN %@", ["Открыть ВКонтакте", "Open ВКонтакте"]))
        vkButtons.firstMatch.press(forDuration: 1.2)
        let copy = button(["Копировать", "Copy"])
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        let duplicate = vkButtons.element(boundBy: 1)
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5)); duplicate.press(forDuration: 1.2)
        let rename = button(["Переименовать", "Rename"])
        XCTAssertTrue(rename.waitForExistence(timeout: 5)); rename.tap()
        let name = app.textFields.matching(NSPredicate(format: "label IN %@", ["Название приложения", "App name"])).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Rename must open the keyboard")
        button(["Сохранить", "Save"]).tap()
        let shortcut = duplicate
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10), "Saving the shortcut must dismiss the form keyboard")
        let shortcutReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = shortcut.frame
            return !frame.isEmpty && ui.frame.contains(frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [shortcutReady], timeout: 10), .completed, "New shortcut must be visible on the desktop")
        shortcut.press(forDuration: 4)
        let remove = app.buttons.matching(NSPredicate(format: "label IN %@", ["Удалить ВКонтакте", "Remove ВКонтакте"])).element(boundBy: 1)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertFalse(button(["Сохранить изображение", "Сохранить фото", "Добавить в Фото", "Save Image", "Save to Photos", "Add to Photos"]).exists)
        remove.tap()
        XCTAssertFalse(button(["Сохранить", "Save"]).exists, "The remove control must not open the shortcut editor")
        XCTAssertTrue(shortcut.waitForNonExistence(timeout: 5), "The remove control must remove the shortcut")
        XCTAssertEqual(vkButtons.count, 1, "Removing the copy must retain the original shortcut")
        emptySpace.tap()
    }

    private func button(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
