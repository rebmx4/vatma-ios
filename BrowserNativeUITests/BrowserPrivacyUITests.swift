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
        screenshot("desktop-new-icon-edit")
        remove.tap()
        XCTAssertFalse(button(["Сохранить", "Save"]).exists, "The remove control must not open the shortcut editor")
        ui.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.25)).tap()
        address.tap(); address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Gesture fixture".count))
    }

    func testSystemHomeEditDurationObservation() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { throw XCTSkip("Measure the iPhone Home Screen baseline") }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        defer { app.activate() }
        let icon = springboard.icons.matching(NSPredicate(format: "label IN %@", ["ATMA", "АТМА"])).firstMatch
        guard icon.waitForExistence(timeout: 8) else { throw XCTSkip("ATMA icon is not accessible on SpringBoard") }
        var observations: [[String: Any]] = []
        func probe(_ seconds: Double) -> Bool {
            icon.press(forDuration: seconds)
            let done = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Готово"])).firstMatch
            let editing = done.waitForExistence(timeout: 0.7)
            observations.append(["seconds": seconds, "editing": editing])
            if editing { done.tap() } else { XCUIDevice.shared.press(.home) }
            return editing
        }
        var lower = 0.0, upper: Double?
        for seconds in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0] {
            if probe(seconds) { upper = seconds; break }
            lower = seconds
        }
        if var bound = upper {
            for _ in 0..<3 {
                let middle = (lower + bound) / 2
                if probe(middle) { bound = middle } else { lower = middle }
            }
            upper = bound
        }
        let result: [String: Any] = ["ios": UIDevice.current.systemVersion, "observations": observations,
                                    "lowerSeconds": lower, "upperSeconds": upper as Any? ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "system-home-edit-duration.json"; attachment.lifetime = .keepAlways; add(attachment)
        print("ATMA_SYSTEM_HOME_EDIT_TIMING " + String(decoding: data, as: UTF8.self))
    }

    private func button(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
