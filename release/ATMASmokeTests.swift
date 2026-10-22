import XCTest

final class ATMASmokeTests: XCTestCase {
  @MainActor
  func testNativeBrowserOpensWebsiteAndSettings() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

    let location = app.descendants(matching: .any).matching(identifier: "url").firstMatch
    let onboardingButtons = [
      "Not Now", "Not now", "Skip", "Maybe Later", "Start Browsing", "Start browsing",
      "Continue", "Get Started", "Get started", "Done", "Let's go", "Let’s go"
    ]
    for _ in 0..<16 {
      if location.exists && location.isHittable { break }
      if let button = onboardingButtons.map({ app.buttons[$0] }).first(where: { $0.exists && $0.isHittable }) {
        button.tap()
      } else {
        _ = location.waitForExistence(timeout: 2)
      }
    }
    XCTAssertTrue(location.waitForExistence(timeout: 15), "The native address bar did not appear")
    assertAtmaLabels(app)
    saveScreenshot(app, name: "ATMA-start")

    location.tap()
    let address = app.textFields.firstMatch
    XCTAssertTrue(address.waitForExistence(timeout: 5))
    address.tap()
    address.typeText("https://example.com\n")
    XCTAssertTrue(app.webViews.staticTexts["Example Domain"].waitForExistence(timeout: 45), "The browser did not load the requested HTTPS page")
    saveScreenshot(app, name: "ATMA-website")

    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    for _ in 0..<8 {
      if location.exists && location.isHittable { break }
      if let button = onboardingButtons.map({ app.buttons[$0] }).first(where: { $0.exists && $0.isHittable }) {
        button.tap()
      } else {
        _ = location.waitForExistence(timeout: 2)
      }
    }
    XCTAssertTrue(location.waitForExistence(timeout: 15), "The browser did not reopen")
    XCTAssertTrue(app.webViews.staticTexts["Example Domain"].waitForExistence(timeout: 45), "The browser did not restore the opened page after relaunch")
    assertAtmaLabels(app)
    saveScreenshot(app, name: "ATMA-reopened")

    let menuButtons = [app.buttons["topToolbarView-menuButton"], app.buttons["TabToolbar.menuButton"], app.buttons["Menu"]]
    guard let menu = menuButtons.first(where: { $0.exists && $0.isHittable }) else {
      XCTFail("The browser menu is missing")
      return
    }
    menu.tap()
    let settings = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(app.tables["SettingsViewController.tableView"].waitForExistence(timeout: 10), "The Settings screen did not open")
    assertAtmaLabels(app)
    saveScreenshot(app, name: "ATMA-settings")
  }

  @MainActor
  private func assertAtmaLabels(_ app: XCUIApplication) {
    for element in app.descendants(matching: .any).allElementsBoundByIndex {
      let label = element.label
      let isLegalNotice = label.localizedCaseInsensitiveContains("copyright") || label.contains("Brave Software") || label.contains("MPL-2.0")
      if !isLegalNotice && label.range(of: #"\bBrave\b"#, options: .regularExpression) != nil {
        XCTFail("Old product branding remains in the interface: \(label)")
      }
    }
  }

  @MainActor
  private func saveScreenshot(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
