import XCTest
import UIKit

final class BrowserSmokeTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testHomeSettingsBlankTabWebsiteAndRelaunch() throws {
        let websiteURL = "https://httpbingo.org/html"
        let headingText = "Herman Melville - Moby-Dick"
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
        var address = app.textFields.firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let value = address.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == address.placeholderValue, "A new tab must have an empty address")
        XCTAssertEqual(siteRenderers.count, 0, "A blank tab must not allocate a site renderer")
        screenshot("blank-tab")

        var go = button(["Перейти", "Go"])
        assertAddressControlsAboveKeyboard()
        rotate(.landscapeLeft, landscape: true)
        address = app.textFields.firstMatch
        address.tap()
        assertAddressControlsAboveKeyboard()
        screenshot("blank-tab-landscape-keyboard")
        rotate(.portrait, landscape: false)
        address = app.textFields.firstMatch
        go = button(["Перейти", "Go"])
        address.tap()
        assertAddressControlsAboveKeyboard()
        address.typeText(websiteURL)
        XCTAssertEqual(address.value as? String, websiteURL, "Typing an address must not hit keyboard keys beneath hidden controls")
        go.tap()
        assertKeyboardDismissed()
        let site = siteRenderers.firstMatch
        XCTAssertTrue(site.waitForExistence(timeout: 5), "Navigation must create an identified site renderer")
        let heading = site.staticTexts[headingText]
        XCTAssertTrue(heading.waitForExistence(timeout: 30), "The independent site renderer must load HTTPS content")
        screenshot("website")

        address.tap()
        assertAddressControlsAboveKeyboard()
        screenshot("website-keyboard")
        go.tap()
        assertKeyboardDismissed()
        XCTAssertTrue(heading.waitForExistence(timeout: 30))

        app.terminate()
        app.launch()
        XCTAssertTrue(button(["Рабочий стол", "Home"]).waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts[headingText].exists, "Relaunch must return to the desktop")
        XCTAssertEqual(siteRenderers.count, 0, "Restored tabs must remain lazy on home launch")
        screenshot("relaunched-home")
    }

    private var siteRenderers: XCUIElementQuery {
        app.webViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "atma.site."))
    }

    private func assertAddressControlsAboveKeyboard() {
        var lastObservation = "Not evaluated"
        let visible = NSPredicate { _, _ in
            // Rotation can replace WebKit accessibility elements. Resolve a
            // fresh query for each poll instead of retaining the earlier match.
            let keyboard = self.app.keyboards.firstMatch
            let accessory = self.app.toolbars.matching(identifier: "Toolbar").firstMatch
            let ui = self.app.webViews.matching(identifier: "atma.ui").firstMatch
            let address = self.app.textFields.firstMatch
            let go = self.button(["Перейти", "Go"])
            let present = [keyboard.exists, ui.exists, address.exists, go.exists]
            lastObservation = "Present keyboard/UI/address/Go: \(present)"
            guard present.allSatisfy({ $0 }) else { return false }
            let bounds = ui.frame
            let keyboardTop = min(keyboard.frame.minY, accessory.exists ? accessory.frame.minY : keyboard.frame.minY)
            let bottom = min(bounds.maxY, keyboardTop)
            let controls = [address, go].map { ($0.frame, $0.isHittable) }
            lastObservation = "UI=\(bounds), keyboardTop=\(keyboardTop), address=\(controls[0]), Go=\(controls[1])"
            return controls.allSatisfy { control in
                let frame = control.0
                return frame.width > 0 && frame.height > 0 && frame.minY >= bounds.minY && frame.maxY <= bottom
                    && frame.minX >= bounds.minX && frame.maxX <= bounds.maxX && control.1
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: visible, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 20)
        if result != .completed {
            print("Address/keyboard check failed: \(lastObservation)")
            screenshot("address-keyboard-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "address-keyboard-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed,
                       "The address field and Go button must stay above the keyboard and its accessory bar: \(lastObservation)")
    }

    private func rotate(_ orientation: UIDeviceOrientation, landscape: Bool) {
        XCUIDevice.shared.orientation = orientation
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed, "The app must support this device orientation")
    }

    private func assertKeyboardDismissed() {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "Submitting an address must dismiss the keyboard")
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
