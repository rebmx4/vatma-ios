import XCTest
import UIKit

/// Production UI and the published help page sources, served locally for repeatable captures.
final class StoreScreenshotsTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // Keep the Russian desktop separate from the unit-test host's saved regional layout.
        app.launchArguments = ["-atma.ui.loopback.port", "28917", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
    }

    @MainActor
    func testCaptureCurrentBrowserForStore() async throws {
        let site = try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("site")
        let paths = ["guide.html", "support.html", "assets/site.css", "assets/atma.png"]
        let resources = try Dictionary(uniqueKeysWithValues: paths.map {
            ("/" + $0, try Data(contentsOf: site.appendingPathComponent($0)))
        })
        let server = try BrowserRenderingFixtureServer(resources: resources)
        defer { server.stop() }
        let root = try await server.start()
        let hostname = try XCTUnwrap(root.host)
        let home = button(["Рабочий стол", "Home"])
        let desktopMenu = button(["Меню браузера", "Browser menu"])
        XCTAssertTrue(desktopMenu.waitForExistence(timeout: 20))
        let firstShortcut = button(["Открыть ВКонтакте", "Open ВКонтакте"])
        waitUntilUsable(firstShortcut, "Home must show actual shortcuts before capture")
        capture("store-ru-01-home")

        desktopMenu.tap()
        button(["Настройки", "Settings"]).tap()
        let privacy = button(["Политика конфиденциальности", "Privacy Policy"])
        waitUntilUsable(privacy, "Privacy policy must be reachable from Settings")
        capture("store-ru-04-settings")
        privacy.tap()
        let policyHeading = app.staticTexts["О приложении"]
        XCTAssertTrue(policyHeading.waitForExistence(timeout: 10), "Bundled policy must open without a website request")
        capture("store-ru-privacy")
        closePanel()

        desktopMenu.tap()
        button(["Настройки", "Settings"]).tap()
        let appearance = button(["Оформление", "Appearance"])
        waitUntilUsable(appearance, "Appearance settings must be usable")
        appearance.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Тема интерфейса", "Interface theme"])).firstMatch.waitForExistence(timeout: 10))
        capture("store-ru-05-appearance")
        closePanel()

        _ = try openWebsite(root.appendingPathComponent("guide.html"), heading: "Как пользоваться ATMA")
        let siteNames = [hostname, "Как пользоваться ATMA · ATMA"]
        let addShortcut = button(siteNames.map { "Добавить \($0) на рабочий стол" })
        let savedShortcut = button(siteNames.map { "\($0) уже на рабочем столе" })
        if !savedShortcut.exists {
            waitUntilUsable(addShortcut, "Quick-add waits for this document to finish loading")
            addShortcut.tap()
            XCTAssertTrue(savedShortcut.waitForExistence(timeout: 20))
        }
        home.tap()
        let shortcut = button(["Открыть Как пользоваться ATMA · ATMA", "Open Как пользоваться ATMA · ATMA"])
        waitUntilUsable(shortcut, "The saved website shortcut must be present")
        shortcut.tap()
        _ = try waitForVisibleSite(heading: "Как пользоваться ATMA")
        XCTAssertFalse(button(["Выбрать устройство", "Choose device"]).isHittable)
        waitUntilUsable(home, "Saved websites retain the compact ATMA home button")
        capture("store-ru-02-compact-website")

        let supportSite = try openWebsite(root.appendingPathComponent("support.html"), heading: "Поддержка")
        let tabs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Открытые вкладки:", "Open tabs:")).firstMatch
        waitUntilUsable(tabs, "Tabs control must remain available")
        tabs.tap()
        let currentTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Открыть вкладку:", "Open tab:")).firstMatch
        waitUntilUsable(currentTab, "Tab cards must be rendered before capture")
        capture("store-ru-03-tabs")
        let supportTab = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND (label BEGINSWITH %@ OR label BEGINSWITH %@)", "Поддержка", "Открыть вкладку:", "Open tab:")).firstMatch
        for _ in 0..<4 {
            if supportTab.isHittable { break }
            app.swipeUp()
        }
        waitUntilUsable(supportTab, "Select the support tab to resume browsing")
        supportTab.tap()
        let emailLink = supportSite.links["a1238585@bk.ru"]
        XCTAssertTrue(emailLink.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if emailLink.isHittable { break }
            supportSite.swipeUp()
        }
        waitUntilUsable(emailLink, "Website contact links must remain usable")
        emailLink.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "External links require explicit confirmation")
        XCTAssertEqual(app.state, .runningForeground)
        confirmation.buttons.matching(NSPredicate(format: "label IN %@", ["Отмена", "Cancel"])).firstMatch.tap()
        home.tap()
    }

    private func waitForVisibleSite(heading: String) throws -> XCUIElement {
        let pages = app.webViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "atma.site."))
        var visibleID: String?
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            visibleID = pages.allElementsBoundByIndex.first { page in
                page.isHittable && page.staticTexts[heading].exists
            }?.identifier
            return visibleID != nil
        }, object: nil)
        let result = XCTWaiter.wait(for: [loaded], timeout: 50)
        if result != .completed {
            let details = XCTAttachment(string: app.debugDescription)
            details.name = "store-site-load-failure"; details.lifetime = .keepAlways; add(details)
            capture("store-site-load-failure")
        }
        XCTAssertEqual(result, .completed, "The visible site must load \(heading)")
        let id = try XCTUnwrap(visibleID)
        return pages.matching(identifier: id).firstMatch
    }

    private func openWebsite(_ url: URL, heading: String) throws -> XCUIElement {
        let home = button(["Рабочий стол", "Home"])
        if home.isHittable { home.tap() }
        let desktopMenu = button(["Меню браузера", "Browser menu"])
        waitUntilUsable(desktopMenu, "Home menu must be available")
        desktopMenu.tap()
        let newTab = button(["Новая вкладка", "New tab"])
        waitUntilUsable(newTab, "New tab must be available")
        newTab.tap()
        let address = app.webViews.matching(identifier: "atma.ui").firstMatch.textFields.firstMatch
        waitUntilUsable(address, "Address must be available to focus")
        address.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Tapping the address must show the keyboard")
        address.typeText(url.absoluteString)
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            address.value as? String == url.absoluteString
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 15), .completed, "Address entry must preserve the exact URL")
        button(["Перейти", "Go"]).tap()
        return try waitForVisibleSite(heading: heading)
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
