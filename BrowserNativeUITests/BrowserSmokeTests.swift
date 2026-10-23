import XCTest

final class BrowserSmokeTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
    }

    func testHomeSettingsBlankTabWebsiteAndRelaunch() throws {
        let home = button(["Рабочий стол", "Home"])
        XCTAssertTrue(home.waitForExistence(timeout: 20), "Bundled native browser UI must load")
        screenshot("home")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "home-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(home.isHittable, "Home controls must be visible and usable")
        XCTAssertTrue(app.webViews.matching(identifier: "atma.ui").firstMatch.exists)
        XCTAssertEqual(siteRenderers.count, 0, "First home launch must not allocate a site renderer")

        let settings = button(["Настройки", "Settings"])
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let close = button(["Закрыть", "Close"])
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Settings panel must open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Настройки", "Settings"])).firstMatch.exists)
        screenshot("settings")
        close.tap()

        let newTab = button(["Новая вкладка", "New tab"])
        XCTAssertTrue(newTab.waitForExistence(timeout: 5))
        newTab.tap()
        let address = app.textFields.firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let value = address.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == address.placeholderValue, "A new tab must have an empty address")
        XCTAssertEqual(siteRenderers.count, 0, "A blank tab must not allocate a site renderer")
        screenshot("blank-tab")

        address.tap()
        address.typeText("https://example.com")
        button(["Перейти", "Go"]).tap()
        let heading = app.staticTexts["Example Domain"]
        XCTAssertTrue(heading.waitForExistence(timeout: 30), "The independent site renderer must load HTTPS content")
        XCTAssertTrue(siteRenderers.firstMatch.exists, "HTTPS content must use an identified site renderer")
        screenshot("website")

        app.terminate()
        app.launch()
        XCTAssertTrue(button(["Рабочий стол", "Home"]).waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Example Domain"].exists, "Relaunch must return to the desktop")
        XCTAssertEqual(siteRenderers.count, 0, "Restored tabs must remain lazy on home launch")
        screenshot("relaunched-home")
    }

    private var siteRenderers: XCUIElementQuery {
        app.webViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "atma.site."))
    }

    private func button(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
