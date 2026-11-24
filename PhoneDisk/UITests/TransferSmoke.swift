import XCTest

final class TransferSmoke: XCTestCase {
    func testUploadDownloadAndPersistentQueue() throws {
        let app=XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"]="1"
        app.launch()
        let attachment=app.buttons["Выбрать пробный файл"]
        XCTAssertTrue(attachment.waitForExistence(timeout:20))
        let backup=app.buttons["Тестовая автовыгрузка"]
        XCTAssertTrue(backup.waitForExistence(timeout:20))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:backup)
        waitForExpectations(timeout:20)
        backup.tap()
        app.buttons["Передача"].tap()
        let completed=app.staticTexts.matching(identifier:"Готово")
        expectation(for:NSPredicate{ _,_ in completed.count==3 },evaluatedWith:app)
        waitForExpectations(timeout:100)
        app.buttons["Готово"].tap()

        let download=app.links["Скачать пробный файл"]
        XCTAssertTrue(download.waitForExistence(timeout:20))
        download.tap()
        attachment.tap()
        app.buttons["Передача"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCUIDevice.shared.press(.home)
        app.activate()
        let finished=NSPredicate{ _,_ in completed.count==5 }
        expectation(for:finished,evaluatedWith:app)
        waitForExpectations(timeout:60)
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        app.terminate()
        app.launch()
        app.buttons["Передача"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        XCTAssertEqual(completed.count,5)
    }
}
