import XCTest
import UIKit

final class BrowserSmokeTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "--atma-ui-diagnostics"]
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testHomeSettingsBlankTabWebsiteAndRelaunch() throws {
        let websiteURL = "https://httpbingo.org/html"
        let headingText = "Herman Melville - Moby-Dick"
        let home = button(["Рабочий стол", "Home"])
        let startupBeginning = Date()
        let homeReadyWithinDeadline = home.waitForExistence(timeout: 20)
        if !homeReadyWithinDeadline {
            screenshot("startup-at-20-seconds")
            let initialHierarchy = XCTAttachment(string: app.debugDescription)
            initialHierarchy.name = "startup-at-20-seconds-hierarchy"
            initialHierarchy.lifetime = .keepAlways
            add(initialHierarchy)
            let remainingObservation = max(0, 60 - Date().timeIntervalSince(startupBeginning))
            let appearedDuringObservation = home.waitForExistence(timeout: remainingObservation)
            print("Startup diagnostic: initial20s=false, appearedLater=\(appearedDuringObservation), elapsed=\(Date().timeIntervalSince(startupBeginning))")
            screenshot("startup-late-observation")
            let finalHierarchy = XCTAttachment(string: app.debugDescription)
            finalHierarchy.name = "startup-late-observation-hierarchy"
            finalHierarchy.lifetime = .keepAlways
            add(finalHierarchy)
        }
        XCTAssertTrue(homeReadyWithinDeadline, "Bundled native browser UI must load within 20 seconds")
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
        XCTAssertTrue(heading.waitForExistence(timeout: 60), "The independent site renderer must load HTTPS content")
        screenshot("website")
        button(["Свернуть выбор устройства"]).tap()
        XCTAssertTrue(address.isHittable, "Hiding the device row must preserve address entry")
        screenshot("website-device-row-hidden")
        button(["Показать выбор устройства"]).tap()
        XCTAssertTrue(button(["Выбрать устройство"]).isHittable)

        address.tap()
        assertAddressControlsAboveKeyboard()
        screenshot("website-keyboard")
        go.tap()
        assertKeyboardDismissed()
        XCTAssertTrue(heading.waitForExistence(timeout: 60))

        let pin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Добавить httpbingo.org")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        XCTAssertTrue(app.buttons["httpbingo.org уже на рабочем столе"].waitForExistence(timeout: 5))
        home.tap()
        let shortcut = button(["Открыть httpbingo.org"])
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        shortcut.tap()
        address = app.textFields.firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertTrue(address.isHittable, "Saved apps always retain their compact address bar")
        XCTAssertTrue(home.isHittable)
        XCTAssertFalse(button(["Выбрать устройство"]).isHittable)
        XCTAssertFalse(button(["Развернуть панель приложения", "Свернуть панель приложения"]).exists)
        XCTAssertTrue(heading.waitForExistence(timeout: 60))
        assertChromeAtPhysicalBottom()
        screenshot("web-app-compact")
        address.tap()
        assertAddressControlsAboveKeyboard()
        button(["Перейти", "Go"]).tap()
        assertKeyboardDismissed()
        XCTAssertTrue(address.isHittable)
        XCTAssertTrue(home.isHittable)
        home.tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "--atma-ui-diagnostics" }
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
                // Read bundled WebKit frames from one accessibility snapshot. Separate
                // firstMatch attribute requests returned zero frames after iPad
                // rotation while the full hierarchy and recording were correct.
                let snapshot = try self.app.snapshot()
                let elements = self.snapshots(in: snapshot)
                guard let windowBounds = self.mainWindowBounds(in: elements) else {
                    lastObservation = "Main window absent from snapshot"
                    return false
                }
                let keyboard = self.app.keyboards.firstMatch
                guard keyboard.exists,
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
                // System input windows can retain a differently oriented frame
                // in an application snapshot. Element queries normalize their
                // coordinates to the current interface orientation.
                let keyboardFrame = keyboard.frame
                guard self.hasVisibleFrame(keyboardFrame, in: windowBounds) else {
                    lastObservation = "Visible keyboard frame unavailable: \(keyboardFrame)"
                    return false
                }
                let accessoryFrame = self.app.toolbars.matching(identifier: "Toolbar").allElementsBoundByIndex
                    .map(\.frame).first { self.hasVisibleFrame($0, in: windowBounds) }
                let bounds = ui.frame
                let keyboardTop = min(keyboardFrame.minY, accessoryFrame?.minY ?? keyboardFrame.minY)
                let bottom = min(bounds.maxY, keyboardTop)
                let frames = [address.frame, go.frame]
                let hittable = [self.app.textFields.firstMatch.isHittable, self.button(["Перейти", "Go"]).isHittable]
                lastObservation = "UI=\(bounds), keyboard=\(keyboardFrame), accessory=\(String(describing: accessoryFrame)), keyboardTop=\(keyboardTop), frames=\(frames), hittable=\(hittable)"
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
        let windowBounds = try XCTUnwrap(mainWindowBounds(in: elements), "Application must have a visible main window")
        let focused = elements.first { $0.elementType == .textField }?.hasFocus == true
        let keyboardVisible = elements.contains { $0.elementType == .keyboard && hasVisibleFrame($0.frame, in: windowBounds) }
        // Tapping an already focused WebKit input opens the system edit menu,
        // which blocks hit testing. Rotation needs a tap only if focus was lost.
        if !focused || !keyboardVisible { app.textFields.firstMatch.tap() }
    }

    private func mainWindowBounds(in elements: [any XCUIElementSnapshot]) -> CGRect? {
        // The application snapshot itself may have no frame. Its main window
        // supplies screen-space bounds for the keyboard and accessory windows.
        elements.first { $0.elementType == .window && $0.frame.width > 0 && $0.frame.height > 0 }?.frame
    }

    private func hasVisibleFrame(_ frame: CGRect, in bounds: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && frame.intersects(bounds)
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

    private func assertChromeAtPhysicalBottom() {
        var observation = "Not evaluated"
        let atBottom = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let snapshot = try? self.app.snapshot() else { return false }
            let elements = self.snapshots(in: snapshot)
            guard let window = self.mainWindowBounds(in: elements),
                  let ui = elements.first(where: { $0.elementType == .webView && $0.identifier == "atma.ui" }) else { return false }
            let controls = self.snapshots(in: ui)
            guard let bottomButton = controls.first(where: { $0.elementType == .button && ["Рабочий стол", "Home", "Развернуть панель приложения"].contains($0.label) && $0.frame.width > 0 && $0.frame.height > 0 }) else { return false }
            let distance = window.maxY - bottomButton.frame.midY
            observation = "window=\(window), ui=\(ui.frame), bottomButton=\(bottomButton.frame), distance=\(distance)"
            return abs(window.maxY - ui.frame.maxY) < 2 && distance > 0 && distance < 80
        }, object: nil)
        let result = XCTWaiter.wait(for: [atBottom], timeout: 5)
        if result != .completed {
            print("Closed-keyboard chrome is raised: \(observation)")
            screenshot("closed-keyboard-bottom-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "closed-keyboard-bottom-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "Closed-keyboard chrome must reach the physical window bottom: \(observation)")
    }

    private func assertKeyboardDismissed() {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "Submitting an address must dismiss the keyboard")
        assertChromeAtPhysicalBottom()
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
