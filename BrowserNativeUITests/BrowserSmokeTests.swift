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
        try focusAddressIfNeeded()
        assertAddressControlsAboveKeyboard()
        screenshot("blank-tab-landscape-keyboard")
        rotate(.portrait, landscape: false)
        address = app.textFields.firstMatch
        go = button(["Перейти", "Go"])
        try focusAddressIfNeeded()
        assertAddressControlsAboveKeyboard()
        address.typeText(websiteURL)
        var observedAddress: String?
        let enteredAddress = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let snapshot = try? self.app.snapshot() else { return false }
            observedAddress = self.snapshots(in: snapshot).first { $0.elementType == .textField }?.value as? String
            return observedAddress == websiteURL
        }, object: nil)
        let entryResult = XCTWaiter.wait(for: [enteredAddress], timeout: 20)
        if entryResult != .completed {
            print("Address input mismatch: expected=\(websiteURL), observed=\(String(describing: observedAddress))")
            screenshot("typed-address-mismatch")
        }
        XCTAssertEqual(entryResult, .completed,
                       "Typing must produce the exact website URL; observed: \(String(describing: observedAddress))")
        go = button(["Перейти", "Go"])
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
            do {
                // Read all frames from one full accessibility snapshot. Separate
                // firstMatch attribute requests returned zero frames after iPad
                // rotation while the full hierarchy and recording were correct.
                let snapshot = try self.app.snapshot()
                let elements = self.snapshots(in: snapshot)
                guard let keyboard = elements.first(where: { $0.elementType == .keyboard && self.hasVisibleFrame($0, in: snapshot.frame) }),
                      let ui = elements.first(where: { $0.elementType == .webView && $0.identifier == "atma.ui" }) else {
                    lastObservation = "Keyboard or bundled UI absent from snapshot"
                    return false
                }
                let controls = self.snapshots(in: ui)
                guard let address = controls.first(where: { $0.elementType == .textField }),
                      let go = controls.first(where: { $0.elementType == .button && ["Перейти", "Go"].contains($0.label) }) else {
                    lastObservation = "Address or Go absent from bundled UI snapshot"
                    return false
                }
                let accessory = elements.first {
                    $0.elementType == .toolbar && $0.identifier == "Toolbar" && self.hasVisibleFrame($0, in: snapshot.frame)
                }
                let bounds = ui.frame
                let keyboardTop = min(keyboard.frame.minY, accessory?.frame.minY ?? keyboard.frame.minY)
                let bottom = min(bounds.maxY, keyboardTop)
                let frames = [address.frame, go.frame]
                let hittable = [self.app.textFields.firstMatch.isHittable, self.button(["Перейти", "Go"]).isHittable]
                lastObservation = "UI=\(bounds), keyboard=\(keyboard.frame), accessory=\(String(describing: accessory?.frame)), keyboardTop=\(keyboardTop), frames=\(frames), hittable=\(hittable)"
                return frames.allSatisfy { frame in
                    frame.width > 0 && frame.height > 0 && frame.minY >= bounds.minY && frame.maxY <= bottom
                        && frame.minX >= bounds.minX && frame.maxX <= bounds.maxX
                } && hittable.allSatisfy { $0 }
            } catch {
                lastObservation = "Accessibility snapshot failed: \(error)"
                return false
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

    private func focusAddressIfNeeded() throws {
        let snapshot = try app.snapshot()
        let elements = snapshots(in: snapshot)
        let focused = elements.first { $0.elementType == .textField }?.hasFocus == true
        let keyboardVisible = elements.contains { $0.elementType == .keyboard && hasVisibleFrame($0, in: snapshot.frame) }
        // Tapping an already focused WebKit input opens the system edit menu,
        // which blocks hit testing. Rotation needs a tap only if focus was lost.
        if !focused || !keyboardVisible { app.textFields.firstMatch.tap() }
    }

    private func hasVisibleFrame(_ element: any XCUIElementSnapshot, in bounds: CGRect) -> Bool {
        element.frame.width > 0 && element.frame.height > 0 && element.frame.intersects(bounds)
    }

    private func snapshots(in root: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        [root] + root.children.flatMap { snapshots(in: $0) }
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
