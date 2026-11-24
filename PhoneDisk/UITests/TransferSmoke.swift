import XCTest

final class TransferSmoke: XCTestCase {
    func testUploadDownloadAndPersistentQueue() throws {
        let app=XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"]="1"
        app.launch()
        let attachment=app.buttons["Выбрать пробный файл"]
        XCTAssertTrue(attachment.waitForExistence(timeout:20))
        let download=app.links["Скачать пробный файл"]
        XCTAssertTrue(download.waitForExistence(timeout:20))
        download.tap()
        attachment.tap()
        app.buttons["Передача"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCUIDevice.shared.press(.home)
        app.activate()
        let completed=app.staticTexts.matching(identifier:"Готово")
        let finished=NSPredicate{ _,_ in completed.count==2 }
        expectation(for:finished,evaluatedWith:app)
        waitForExpectations(timeout:60)
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        app.terminate()
        app.launch()
        app.buttons["Передача"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        XCTAssertEqual(completed.count,2)
    }
}
