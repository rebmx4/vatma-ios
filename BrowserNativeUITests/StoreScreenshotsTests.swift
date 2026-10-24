import XCTest
import UIKit

/// Real production UI and public help pages: no injected store-only application state.
final class StoreScreenshotsTests: XCTestCase {
    private let app = XCUIApplication()
    private let baseURL = "https://rebmx4.github.io/vatma-ios/"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
    }

    func testCaptureCurrentBrowserForStore() throws {
        let home = button(["Рабочий стол", "Home"])
        XCTAssertTrue(home.waitForExistence(timeout: 20))
        home.tap()
        let firstShortcut = button(["Открыть ВКонтакте", "Open ВКонтакте"])
        waitUntilUsable(firstShortcut, "Home must show actual shortcuts before capture")
        capture("store-ru-01-home")

        button(["Настройки", "Settings"]).tap()
        let privacy = button(["Политика конфиденциальности", "Privacy Policy"])
        waitUntilUsable(privacy, "Privacy policy must be reachable from Settings")
        capture("store-ru-04-settings")
        privacy.tap()
        let policyHeading = app.staticTexts["О приложении"]
        XCTAssertTrue(policyHeading.waitForExistence(timeout: 10), "Bundled policy must open without a website request")
        capture("store-ru-privacy")
        closePanel()

        button(["Настройки", "Settings"]).tap()
        let appearance = button(["Оформление", "Appearance"])
        waitUntilUsable(appearance, "Appearance settings must be usable")
        appearance.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Тема интерфейса", "Interface theme"])).firstMatch.waitForExistence(timeout: 10))
        capture("store-ru-05-appearance")
        closePanel()

        try openWebsite("guide.html", heading: "Как пользоваться ATMA")
        let addShortcut = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Добавить ", "rebmx4.github.io")).firstMatch
        let savedShortcut = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label ENDSWITH %@", "rebmx4.github.io", "уже на рабочем столе")).firstMatch
        if !savedShortcut.exists {
            waitUntilUsable(addShortcut, "Quick-add waits for this document to finish loading")
            addShortcut.tap()
            XCTAssertTrue(savedShortcut.waitForExistence(timeout: 20))
        }
        home.tap()
        let shortcut = button(["Открыть Как пользоваться ATMA · ATMA", "Open Как пользоваться ATMA · ATMA"])
        waitUntilUsable(shortcut, "The saved website shortcut must be present")
        shortcut.tap()
        XCTAssertTrue(site.staticTexts["Как пользоваться ATMA"].waitForExistence(timeout: 50))
        XCTAssertFalse(button(["Выбрать устройство", "Choose device"]).isHittable)
        waitUntilUsable(home, "Saved websites retain the compact ATMA home button")
        capture("store-ru-02-compact-website")

        try openWebsite("support.html", heading: "Поддержка")
        let tabs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Открытые вкладки:", "Open tabs:")).firstMatch
        waitUntilUsable(tabs, "Tabs control must remain available")
        tabs.tap()
        let currentTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Открыть вкладку:", "Open tab:")).firstMatch
        waitUntilUsable(currentTab, "Tab cards must be rendered before capture")
        capture("store-ru-03-tabs")
        closePanel()
        let emailLink = site.links["a1238585@bk.ru"]
        XCTAssertTrue(emailLink.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if emailLink.isHittable { break }
            site.swipeUp()
        }
        waitUntilUsable(emailLink, "Website contact links must remain usable")
        emailLink.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "External links require explicit confirmation")
        XCTAssertEqual(app.state, .runningForeground)
        confirmation.buttons.matching(NSPredicate(format: "label IN %@", ["Отмена", "Cancel"])).firstMatch.tap()
        home.tap()
    }

    private var site: XCUIElement {
        app.webViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "atma.site.")).firstMatch
    }

    private func openWebsite(_ path: String, heading: String) throws {
        let home = button(["Рабочий стол", "Home"])
        waitUntilUsable(home, "Return to the full browser controls before opening a tab")
        home.tap()
        let newTab = button(["Новая вкладка", "New tab"])
        waitUntilUsable(newTab, "New tab must be available")
        newTab.tap()
        let address = app.textFields.firstMatch
        waitUntilUsable(address, "Address must be ready for typing")
        let url = baseURL + path
        address.typeText(url)
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            address.value as? String == url
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 15), .completed, "Address entry must preserve the exact URL")
        button(["Перейти", "Go"]).tap()
        XCTAssertTrue(site.staticTexts[heading].waitForExistence(timeout: 50), "Public help page must actually load")
    }

    private func waitUntilUsable(_ element: XCUIElement, _ message: String) {
        let usable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable && element.isEnabled && element.frame.height > 0
        }, object: nil)
        let result = XCTWaiter.wait(for: [usable], timeout: 15)
        if result != .completed {
            let details = XCTAttachment(string: app.debugDescription)
            details.name = "store-capture-failure"; details.lifetime = .keepAlways; add(details)
            capture("store-capture-failure")
        }
        XCTAssertEqual(result, .completed, message)
    }

    private func closePanel() {
        button(["Закрыть", "Close"]).tap()
    }

    private func button(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func capture(_ name: String) {
        let image = app.screenshot()
        let size = UIImage(data: image.pngRepresentation)?.size
        XCTAssertNotNil(size)
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
